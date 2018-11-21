package format.jpg;
// NanoJPEG -- KeyJ's Tiny Baseline JPEG Decoder
// version 1.3 (2012-03-05)
// by Martin J. Fiedler <martin.fiedler@gmx.net>
//
// This software is published under the terms of KeyJ's Research License,
// version 0.2. Usage of this software is subject to the following conditions:
// 0. There's no warranty whatsoever. The author(s) of this software can not
//    be held liable for any damages that occur when using this software.
// 1. This software may be used freely for both non-commercial and commercial
//    purposes.
// 2. This software may be redistributed freely as long as no fees are charged
//    for the distribution and this license information is included.
// 3. This software may be modified freely except for this license information,
//    which must not be changed in any way.
// 4. If anything other than configuration, indentation or comments have been
//    altered in the code, the original author(s) must receive a copy of the
//    modified code.
/* Ported to Haxe by Nicolas Cannasse */

// Rearrange code to provide "Reader" for Format library WIP -  by Nanjizal 
// flash aspects commented out not needed on flash target?
// flash target is becoming irrelevant feel free to test, and add if you require.
// 
import haxe.ds.Vector;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.Input;
@:enum
abstract Filter( Int ) from Int to Int {
    var Fast = 0;
    var Chromatic = 1;
}
abstract FastBytes( haxe.io.Bytes ){
    public inline function new( b: haxe.io.Bytes ) {
        this = b;
    }
    @:arrayAccess inline function get( i: Int ){
        return this.get( i );
    }
    @:arrayAccess inline function set( i: Int, v ) {
        this.set( i, v );
    }
}
class Component {
    public var cid : Int;
    public var ssx : Int;
    public var ssy : Int;
    public var width : Int;
    public var height : Int;
    public var stride : Int;
    public var qtsel : Int;
    public var actabsel : Int;
    public var dctabsel : Int;
    public var dcpred : Int;
    public var pixels : haxe.io.Bytes;
    public function new(){}
}
class Reader {
    var bytesInput: BytesInput;
    var bytes: haxe.io.Bytes;
    static inline var BLOCKSIZE = 64;
    var pos : Int;
    var size : Int;
    var length : Int;
    var width : Int;
    var height : Int;
    var ncomp : Int;
    var comps : Vector<Component>;
    var counts : Vector<Int>;
    var qtab : Vector<Vector<Int>>;
    var qtused : Int;
    var qtavail : Int;
    var vlctab : Vector<haxe.io.Bytes>;
    var block : Vector<Int>;
    var ZZ : Vector<Int>;
    var progressive : Bool;
    var mbsizex : Int;
    var mbsizey : Int;
    var mbwidth : Int;
    var mbheight : Int;
    var rstinterval : Int;
    var buf : Int;
    var bufbits : Int;
    var pixels : Bytes;
    var filter : Filter;
    var vlcCode : Int;
    
    public function new( bytesInput_: BytesInput ){
        bytesInput = bytesInput_;
        bytesInput.bigEndian = false;
        var l = bytesInput.length;
        bytes = alloc( l );
        bytesInput.position = 0;
        bytesInput.readBytes( bytes, 0, l );
    }
    function setComps(){
        comps = haxe.ds.Vector.fromArrayCopy( [ new Component(), new Component(), new Component() ]);
    }
    function setQtab(){
        qtab = haxe.ds.Vector.fromArrayCopy( [ new Vector( 64 ), new Vector( 64 ), new Vector( 64 ), new Vector( 64 ) ]);
    }
    inline function setZZ(){
        ZZ = haxe.ds.Vector.fromArrayCopy( 
            [ 0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63 ] );
    }
    inline function setVlctab(){
        vlctab = haxe.ds.Vector.fromArrayCopy( [ null, null, null, null, null, null, null, null ] );
    }
    public function read( ?filter_, pos_ : Int = 0, size_ : Int = -1 ): Data {
        setComps();
        setQtab();
        counts = new haxe.ds.Vector( 16 );
        block = new haxe.ds.Vector( BLOCKSIZE );
        setZZ();
        setVlctab();
        pos = pos_;
        filter = filter_ == null ? Chromatic : filter_;
        if( size_ < 0 ) size_ = bytes.length - pos;
        for( i in 0...4 ) if( vlctab[ i ] == null ) vlctab[ i ] = alloc( 1 << 17 );
        size = size_;
        qtused = 0;
        qtavail = 0;
        rstinterval = 0;
        length = 0;
        buf = 0;
        bufbits = 0;
        progressive = false;
        for( i in 0...3 ) comps[ i ].dcpred = 0;
        // decode
        if( size < 2 || get( 0 ) != 0xFF || get( 1 ) != 0xD8 ) throw "This file is not a JPEG";
        skip( 2 );
        while( true ) {
            syntax( size < 2 || get( 0 ) != 0xFF );
            skip( 2 );
            switch( get( -1 ) ){
                case 0xC0:
                    _SOF();
                case 0xC2:
                    noProgressive();
                case 0xDB:
                    _DQT();
                case 0xC4:
                    _DHT();
                case 0xDD:
                    _DRI();
                case 0xDA:
                    _scan();
                    break; // DONE
                case 0xFE:
                    skipMarker(); // comment
                case 0xC3: 
                    throw "Unsupported lossless JPG";
                default:
                    _none();
            }
        }
        var pixels = convert();
        cleanup();
        return { pixels : pixels, width : width, quality: 0, height : height };
    }
    function notSupported() throw "This JPG file is not supported";
    inline function _none(){
        switch( get( -1 ) & 0xF0 ){
            case 0xE0:
                skipMarker();
            case 0xC0:
                throw "Unsupported jpeg type " + Std.string( ( get( -1 ) & 0xF ) );
            default:
                throw "Unsupported jpeg tag 0x" + StringTools.hex( get( -1 ), 2 );
        }
    }
    inline function noProgressive(){
        progressive = true;
        if( progressive ) throw "Unsupported progressive JPG";
        for( i in 4...8 ) if( vlctab[ i ] == null ) vlctab[ i ] = alloc( 1 << 17 );
        _SOF();
    }
    inline function alloc( nbytes : Int ) {
        return Bytes.alloc( nbytes );
    }
    inline function free( bytes: Bytes ) {}
    function cleanup(){
        bytes = null;
        cleanupComps();
        cleanupVlctab();
    }
    inline function cleanupComps(){
        for( c in comps ){
            if( c.pixels != null ) {
                free( c.pixels );
                c.pixels = null;
            }
        }
    }
    inline function cleanupVlctab(){
        for( i in 0...8 ){
            if( vlctab[ i ] != null ) {
                free( vlctab[ i ] );
                vlctab[ i ] = null;
            }
        }
    }
    inline function skip( count ) {
        pos += count;
        size -= count;
        length -= count;
        syntax( size < 0 );
    }
    inline function syntax( flag ) {
        #if debug
        if( flag ) throw "Invalid JPEG file";
        #end
    }
    inline function get( p ) {
        return bytes.get( pos + p );
    }
    inline function sixteen( p ) {
        return ( get( p ) << 8 ) | get( p + 1 );
    }
    inline function byteAlign() {
        bufbits &= 0xF8;
    }
    function _SOF() {
        _length();
        syntax( length < 9 );
        if( get( 0 ) != 8 ) notSupported();
        height = sixteen( 1 );
        width = sixteen( 3 );
        ncomp = get( 5 );
        skip( 6 );
        switch( ncomp ) {
            case 1,3:
            default:
                notSupported();
        }
        syntax( length < ncomp * 3 );
        var ssxmax = 0, ssymax = 0;
        for( i in 0...ncomp ) {
            var c = comps[i];
            c.cid = get( 0 );
            c.ssx = get( 1 ) >> 4;
            syntax(c.ssx == 0);
            if( c.ssx & (c.ssx - 1) != 0 ) notSupported();  // non-power of two
            c.ssy = get( 1 ) & 15;
            syntax( c.ssy == 0 );
            if( c.ssy & (c.ssy - 1) != 0 ) notSupported();  // non-power of two
            c.qtsel = get( 2 );
            syntax(c.qtsel & 0xFC != 0 );
            skip( 3 );
            qtused |= 1 << c.qtsel;
            if (c.ssx > ssxmax) ssxmax = c.ssx;
            if (c.ssy > ssymax) ssymax = c.ssy;
        }
        if( ncomp == 1 ) {
            var c = comps[ 0 ];
            c.ssx = c.ssy = ssxmax = ssymax = 1;
        }
        mbsizex = ssxmax << 3;
        mbsizey = ssymax << 3;
        mbwidth = Std.int((width + mbsizex - 1) / mbsizex);
        mbheight = Std.int((height + mbsizey - 1) / mbsizey);
        for( i in 0...ncomp ) {
            var c = comps[i];
            c.width = Std.int((width * c.ssx + ssxmax - 1) / ssxmax);
            c.stride = (c.width + 7) & 0x7FFFFFF8;
            c.height = Std.int((height * c.ssy + ssymax - 1) / ssymax);
            c.stride = Std.int(mbwidth * mbsizex * c.ssx / ssxmax);
            if( (c.width < 3 && c.ssx != ssxmax) || (c.height < 3 && c.ssy != ssymax) ) notSupported();
            c.pixels = alloc(c.stride * Std.int(mbheight * mbsizey * c.ssy / ssymax));
        }
        skip(length);
    }
    function _DQT(){
        _length();
        while( length >= 65 ) {
            var i = get(0);
            syntax( i & 0xFC != 0 );
            qtavail |= 1 << i;
            var t = qtab[ i ];
            for( k in 0...64 ) t[ k ] = get( k + 1 );
            skip( 65 );
        }
        syntax( length != 0 );
    }
    function _DHT(){
        _length();
        while( length >= 17 ) {
            var i = get( 0 );
            syntax( i & 0xEC != 0 );
            i = (( i >> 4 ) & 1) | (( i & 3 ) << 1);  // combined DC/AC + tableid value (put DC/AC in lower bit)
            for( codelen in 0...16) counts[ codelen ] = get( codelen + 1 );
            skip(17);
            var vlc = vlctab[i];
            var vpos = 0;
            var remain = 65536, spread = 65536;
            for( codelen in 1...17 ){
                spread >>= 1;
                var currcnt = counts[ codelen - 1 ];
                if( currcnt == 0 ) continue;
                syntax( length < currcnt );
                remain -= currcnt << ( 16 - codelen );
                syntax( remain < 0 );
                for( i in 0...currcnt ) {
                    var code = get( i );
                    for( j in 0...spread ) {
                        vlc.set( vpos++, codelen );
                        vlc.set( vpos++, code );
                    }
                }
                skip(currcnt);
            }
            while( remain-- != 0 ) {
                vlc.set( vpos, 0 );
                vpos += 2;
            }
        }
        syntax( length != 0 );
    }
    function _DRI(){
        _length();
        syntax( length < 2 );
        rstinterval = sixteen( 0 );
        skip(length);
    }
    inline function _length(){
        syntax( size < 2 );
        length = sixteen( 0 );
        syntax( length > size );
        skip(2);
    }
    function _scan(){
        _length();
        syntax( length < 4 + 2 * ncomp );
        if( get( 0 ) != ncomp ) notSupported();
        skip( 1 );
        for( i in 0...ncomp ) {
            var c = comps[ i ];
            syntax( get( 0 ) != c.cid );
            syntax( get( 1 ) & 0xEC != 0 );
            c.dctabsel = ( get( 1 ) >> 4 ) << 1;
            c.actabsel = ( ( get( 1 ) & 3) << 1 ) | 1;
            skip( 2 );
        }
        var start = get( 0 );
        var count = get( 1 );
        var other = get( 2 );
        if( (!progressive && start != 0) || (count != 63 - start) || other != 0 ) notSupported();
        skip( length );
        var mbx = 0;
        var mby = 0;
        var rstcount = rstinterval, nextrst = 0;
        while( true ) {
            for( i in 0...ncomp ) {
                var c = comps[ i ];
                for( sby in 0...c.ssy ) for( sbx in 0...c.ssx )
                        _block( c, (( mby * c.ssy + sby ) * c.stride + mbx * c.ssx + sbx) << 3 );
            }
            if( ++mbx >= mbwidth ) {
                mbx = 0;
                if( ++mby >= mbheight ) break;
            }
            if( rstinterval != 0 && --rstcount == 0 ) {
                byteAlign();
                var i = getBits(16);
                syntax( i & 0xFFF8 != 0xFFD0 || i & 7 != nextrst );
                nextrst = (nextrst + 1) & 7;
                rstcount = rstinterval;
                for( i in 0...3 ) comps[i].dcpred = 0;
            }
        }
    }
    function _block( c : Component, po ){
        var out = new FastBytes( c.pixels );
        var value, coef = 0;
        for( i in 0...BLOCKSIZE ) block[ i ] = 0;
        c.dcpred += getVLC( vlctab[ c.dctabsel ] );
        var qt = qtab[ c.qtsel ];
        var at = vlctab[ c.actabsel ];
        block[ 0 ] = c.dcpred * qt[ 0 ];
        do {
            value = getVLC( at );
            if( vlcCode == 0 ) break;  // EOB
            syntax( vlcCode & 0x0F == 0 && vlcCode != 0xF0 );
            coef += ( vlcCode >> 4 ) + 1;
            syntax( coef > 63 );
            block[ ZZ[ coef ] ] = value * qt[ coef ];
        } while ( coef < 63 );
        for( coef in 0...8 ) rowIDCT( coef * 8 );
        for( coef in 0...8 ) colIDCT( coef, out, coef + po, c.stride );
    }
    function convert(){
        for( i in 0...ncomp ) {
            var c = comps[ i ];
            switch( filter ) {
            case Fast:
                if( c.width < width || c.height < height ) upsample( c );
            case Chromatic:
                while( c.width < width || c.height < height ) {
                    if( c.width < width )   upsampleH( c );
                    if( c.height < height ) upsampleV( c );
                }
            }
            if( c.width < width || c.height < height ) throw "assert";
        }
        var pixels = alloc(width * height * 4);
        if( ncomp == 3 ) {
            // convert to RGB
            var py =  new FastBytes( comps[ 0 ].pixels );
            var pcb = new FastBytes( comps[ 1 ].pixels );
            var pcr = new FastBytes( comps[ 2 ].pixels );
            /*#if flash
            var dat = pixels.getData();
            if( dat.length < 1024 ) dat.length = 1024;
            flash.Memory.select(dat);
            inline function write(out, c) {
                flash.Memory.setByte(out, c);
            }
            #else */
            var pix = new FastBytes( pixels );
            inline function write( out, c ) {
                pix[ out ] = c;
            }
            //#end
            var k1 = 0, k2 = 0, k3 = 0, out = 0;
            for( yy in 0...height ) {
                for( x in 0...width ) {
                    var y  = py[  k1++ ] << 8;
                    var cb = pcb[ k2++ ] - 128;
                    var cr = pcr[ k3++ ] - 128;
                    var r = clip( ( y + 359 * cr + 128 ) >> 8 );
                    var g = clip( ( y -  88 * cb - 183 * cr + 128 ) >> 8 );
                    var b = clip( ( y + 454 * cb + 128 ) >> 8 );
                    write( out++, b );
                    write( out++, g );
                    write( out++, r );
                    write( out++, 0xFF );
                }
                k1 += comps[ 0 ].stride - width;
                k2 += comps[ 1 ].stride - width;
                k3 += comps[ 2 ].stride - width;
            }
        } else {
            // grayscale -> only remove stride
            throw "TODO";
            /*
            unsigned char *pin = &nj.comp[0].pixels[nj.comp[0].stride];
            unsigned char *pout = &nj.comp[0].pixels[nj.comp[0].width];
            int y;
            for (y = nj.comp[0].height - 1;  y;  --y) {
                njCopyMem(pout, pin, nj.comp[0].width);
                pin += nj.comp[0].stride;
                pout += nj.comp[0].width;
            }
            nj.comp[0].stride = nj.comp[0].width;
            */
        }
        return pixels;
    }
    function upsample( c : Component ){
        var xshift = 0; 
        var yshift = 0;
        while( c.width < width ){ 
            c.width <<= 1; 
            ++xshift; 
        }
        while( c.height < height ){ 
            c.height <<= 1; 
            ++yshift; 
        }
        var out = alloc( c.width * c.height );
        var lin = new FastBytes( c.pixels );
        var pout = 0;
        /*
        #if flash
        var dat = out.getData();
        if( dat.length < 1024 ) dat.length = 1024;
        flash.Memory.select(dat);
        inline function write(pos, v) {
            flash.Memory.setByte(pos, v);
        }
        #else */
        var lout = new FastBytes( out );
        inline function write( pos, v ) lout[ pos ] = v;
        // #end
        for( y in 0...c.height ) {
            var pin = ( y >> yshift ) * c.stride;
            for( x in 0...c.width ) write( pout++, lin[ ( x >> xshift ) + pin ] );
        }
        c.stride = c.width;
        free( c.pixels );
        c.pixels = out;
    }
    function upsampleH( c : Component ){
        var xmax = c.width - 3;
        //unsigned char *out, *lin, *lout;
        //int x, y;
        var cout = alloc( ( c.width * c.height ) << 1);
        var lout = new FastBytes( cout );
        var lin = new FastBytes( c.pixels );
        var pi = 0;
        var po = 0;
        for( y in 0...c.height ) {
            lout[ po ]     = CF( CF2A * lin[ pi ] + CF2B * lin[ pi + 1 ] );
            lout[ po + 1 ] = CF( CF3X * lin[ pi ] + CF3Y * lin[ pi + 1 ] + CF3Z * lin[ pi + 2 ] );
            lout[ po + 2 ] = CF( CF3A * lin[ pi ] + CF3B * lin[ pi + 1 ] + CF3C * lin[ pi + 2 ] );
            for( x in 0...xmax ){
                lout[ po + ( x << 1 ) + 3] =  CF( CF4A * lin[ pi + x ] 
                                            + CF4B * lin[ pi + x + 1 ]
                                            + CF4C * lin[ pi + x + 2 ]
                                            + CF4D * lin[ pi + x + 3 ] );
                lout[ po + ( x << 1 ) + 4] =  CF( CF4D * lin[ pi + x ]
                                            + CF4C * lin[ pi + x + 1 ]
                                            + CF4B * lin[ pi + x + 2 ]
                                            + CF4A * lin[ pi + x + 3 ] );
            }
            pi += c.stride;
            po += c.width << 1;
            lout[ po - 3 ] = CF( CF3A * lin[ pi - 1 ] + CF3B * lin[ pi - 2 ] + CF3C * lin[ pi - 3 ] );
            lout[ po - 2 ] = CF( CF3X * lin[ pi - 1 ] + CF3Y * lin[ pi - 2 ] + CF3Z * lin[ pi - 3 ] );
            lout[ po - 1 ] = CF( CF2A * lin[ pi - 1 ] + CF2B * lin[ pi - 2 ] );
        }
        c.width <<= 1;
        c.stride = c.width;
        free(c.pixels);
        c.pixels = cout;
    }
    function upsampleV( c : Component ){
        var w = c.width;
        var s1 = c.stride;
        var s2 = s1 + s1;
        var out = alloc( ( c.width * c.height ) << 1 );
        var pi = 0;
        var po = 0;
        var cout = new FastBytes( out );
        var cin = new FastBytes( c.pixels );
        for( x in 0...w ) {
            pi = po = x;
            cout[ po ] = CF( CF2A * cin[ pi ] + CF2B * cin[ pi + s1 ] );
            po += w;
            cout[ po ] = CF( CF3X * cin[ pi ] + CF3Y * cin[ pi + s1 ] + CF3Z * cin[ pi + s2 ] );
            po += w;
            cout[ po ] = CF( CF3A * cin[ pi ] + CF3B * cin[ pi + s1 ] + CF3C * cin[ pi + s2 ] );
            po += w;
            pi += s1;
            for( y in 0...c.height - 2 ) {
                cout[ po ] = CF( CF4A * cin[ pi - s1 ] + CF4B * cin[ pi ] + CF4C * cin[ pi + s1 ] + CF4D * cin[ pi + s2 ] );  
                po += w;
                cout[ po ] = CF( CF4D * cin[ pi - s1 ] + CF4C * cin[ pi ] + CF4B * cin[ pi + s1 ] + CF4A * cin[ pi + s2 ] );  
                po += w;
                pi += s1;
            }
            pi += s1;
            cout[ po ] = CF( CF3A * cin[ pi ] + CF3B * cin[ pi - s1 ] + CF3C * cin[ pi - s2 ] );
            po += w;
            cout[ po ] = CF( CF3X * cin[ pi ] + CF3Y * cin[ pi - s1 ] + CF3Z * cin[ pi - s2 ] );
            po += w;
            cout[ po ] = CF( CF2A * cin[ pi ] + CF2B * cin[ pi - s1 ]);
        }
        c.height <<= 1;
        c.stride = c.width;
        free( c.pixels );
        c.pixels = out;
    }
    inline function getVLC( vlc : haxe.io.Bytes ) {
        var value = showBits( 16 );
        var bits = vlc.get( value << 1 );
        syntax( bits == 0 );
        skipBits( bits );
        value = vlc.get( ( value << 1 ) | 1 );
        vlcCode = value;
        bits = value & 15;
        if( bits == 0 ) return 0;
        value = getBits( bits );
        if( value < ( 1 << ( bits - 1 ) ) ) value += ( ( -1 ) << bits ) + 1;
        return value;
    }
    function showBits( bits ) {
        if( bits == 0 ) return 0;
        while( bufbits < bits ){
            if( size <= 0 ){
                buf = ( buf << 8 ) | 0xFF;
                bufbits += 8;
                continue;
            }
            var newbyte = get( 0 );
            pos++;
            size--;
            bufbits += 8;
            buf = ( buf << 8 ) | newbyte;
            if( newbyte == 0xFF ) {
                syntax( size == 0 );
                var marker = get( 0 );
                pos++;
                size--;
                switch (marker) {
                    case 0x00, 0xFF:
                    case 0xD9:
                        size = 0;
                    default:
                        syntax( marker & 0xF8 != 0xD0 );
                        buf = ( buf << 8 ) | marker;
                        bufbits += 8;
                }
            }
        }
        return ( buf >> ( bufbits - bits ) ) & ( ( 1 << bits ) - 1 );
    }
    
    inline function skipBits( bits ) {
        if( bufbits < bits ) showBits( bits );
        bufbits -= bits;
    }
    inline function getBits( bits ){
        var r = showBits( bits );
        bufbits -= bits;
        return r;
    }
    inline function skipMarker(){
        _length();
        skip( length );
    }
    inline static function clip( x ){
        return x < 0 ? 0 : x > 0xFF ? 0xFF : x;
    }
    static inline var CF4A = -9;
    static inline var CF4B = 111;
    static inline var CF4C = 29;
    static inline var CF4D = -3;
    static inline var CF3A = 28;
    static inline var CF3B = 109;
    static inline var CF3C = -9;
    static inline var CF3X = 104;
    static inline var CF3Y = 27;
    static inline var CF3Z = -3;
    static inline var CF2A = 139;
    static inline var CF2B = -11;
    static inline function CF( x ) return clip( ( ( x ) + 64 ) >> 7 );
    static inline var W1 = 2841;
    static inline var W2 = 2676;
    static inline var W3 = 2408;
    static inline var W5 = 1609;
    static inline var W6 = 1108;
    static inline var W7 = 565;
    inline function rowIDCT( bp ) {
        var x1 = block[ bp + 4 ] << 11;
        var x2 = block[ bp + 6 ];
        var x3 = block[ bp + 2 ];
        var x4 = block[ bp + 1 ];
        var x5 = block[ bp + 7 ];
        var x6 = block[ bp + 5 ];
        var x7 = block[ bp + 3 ];
        if( ( x1 | x2| x3| x4 | x5 | x6 | x7 ) == 0 ) {
            var tmp =  block[ bp + 0 ] << 3;
            block[ bp + 0 ] = tmp;
            block[ bp + 1 ] = tmp;
            block[ bp + 2 ] = tmp;
            block[ bp + 3 ] = tmp;
            block[ bp + 4 ] = tmp;
            block[ bp + 5 ] = tmp;
            block[ bp + 6 ] = tmp;
            block[ bp + 7 ] = tmp;
            return;
        }
        var x0 = ( block[ bp + 0 ] << 11 ) + 128;
        var x8 =  W7 * ( x4 + x5 );
        x4 =  x8 + ( W1 - W7 ) * x4;
        x5 =  x8 - ( W1 + W7 ) * x5;
        x8 =  W3 * ( x6 + x7 );
        x6 =  x8 - ( W3 - W5 ) * x6;
        x7 =  x8 - ( W3 + W5 ) * x7;
        x8 =  x0 + x1;
        x0 -= x1;
        x1 =  W6 * ( x3 + x2 );
        x2 =  x1 - ( W2 + W6 ) * x2;
        x3 =  x1 + ( W2 - W6 ) * x3;
        x1 =  x4 + x6;
        x4 -= x6;
        x6 =  x5 + x7;
        x5 -= x7;
        x7 =  x8 + x3;
        x8 -= x3;
        x3 =  x0 + x2;
        x0 -= x2;
        x2 = ( 181 * ( x4 + x5 ) + 128 ) >> 8;
        x4 = ( 181 * ( x4 - x5 ) + 128 ) >> 8;
        block[ bp + 0 ] = ( x7 + x1 ) >> 8;
        block[ bp + 1 ] = ( x3 + x2 ) >> 8;
        block[ bp + 2 ] = ( x0 + x4 ) >> 8;
        block[ bp + 3 ] = ( x8 + x6 ) >> 8;
        block[ bp + 4 ] = ( x8 - x6 ) >> 8;
        block[ bp + 5 ] = ( x0 - x4 ) >> 8;
        block[ bp + 6 ] = ( x3 - x2 ) >> 8;
        block[ bp + 7 ] = ( x7 - x1 ) >> 8;
    }
    inline function colIDCT( bp, out : FastBytes, po, stride ) {
        var x0;
        var x1 = block[ bp + 8*4 ] << 8;
        var x2 = block[ bp + 8*6 ];
        var x3 = block[ bp + 8*2 ];
        var x4 = block[ bp + 8*1 ];
        var x5 = block[ bp + 8*7 ];
        var x6 = block[ bp + 8*5 ];
        var x7 = block[ bp + 8*3 ];
        if( ( x1 | x2 | x3 | x4 | x5 | x6 | x7 ) == 0 ){
            x1 = clip( ( ( block[ bp + 0 ] + 32 ) >> 6 ) + 128 );
            for( i in 0...8 ) {
                out[ po ] = x1;
                po += stride;
            }
            return;
        }
        var x0 = ( block[ bp + 0 ] << 8 ) + 8192;
        var x8 =  W7 * ( x4 + x5 ) + 4;
        x4 =  ( x8 + ( W1 - W7 ) * x4 ) >> 3;
        x5 =  ( x8 - ( W1 + W7 ) * x5 ) >> 3;
        x8 =  W3 * ( x6 + x7 ) + 4;
        x6 =  ( x8 - ( W3 - W5 ) * x6 ) >> 3;
        x7 =  ( x8 - ( W3 + W5 ) * x7 ) >> 3;
        x8 =  x0 + x1;
        x0 -= x1;
        x1 =  W6 * ( x3 + x2 ) + 4;
        x2 =  ( x1 - ( W2 + W6 ) * x2 ) >> 3;
        x3 =  ( x1 + ( W2 - W6 ) * x3 ) >> 3;
        x1 =  x4 + x6;
        x4 -= x6;
        x6 =  x5 + x7;
        x5 -= x7;
        x7 =  x8 + x3;
        x8 -= x3;
        x3 =  x0 + x2;
        x0 -= x2;
        x2 = ( 181 * ( x4 + x5 ) + 128 ) >> 8;
        x4 = ( 181 * ( x4 - x5 ) + 128 ) >> 8;
        out[ po ] = clip( ( ( x7 + x1 ) >> 14 ) + 128 );
        po += stride;
        out[ po ] = clip( ( ( x3 + x2 ) >> 14 ) + 128 );
        po += stride;
        out[ po ] = clip( ( ( x0 + x4 ) >> 14 ) + 128 );
        po += stride;
        out[ po ] = clip( ( ( x8 + x6 ) >> 14 ) + 128 );
        po += stride;
        out[ po ] = clip( ( ( x8 - x6 ) >> 14 ) + 128 );
        po += stride;
        out[ po ] = clip( ( ( x0 - x4 ) >> 14 ) + 128 );
        po += stride;
        out[ po ] = clip( ( ( x3 - x2 ) >> 14 ) + 128 );
        po += stride;
        out[ po ] = clip( ( ( x7 - x1 ) >> 14 ) + 128 );
    }
}
