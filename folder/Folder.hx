package folder;
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileOutput;
import sys.FileSystem;
import format.png.Writer;
import format.png.Tools;
import format.bmp.Writer;
import format.bmp.Tools;
import format.gif.Writer;
import format.gif.Tools;
import haxe.io.Path;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import hxPixels.Pixels;
#if neko
import neko.vm.Module;
#end
typedef ImageSpec = {
    fileSpec: FileSpec,
    pixels: Pixels
}
typedef FileSpec = {
    name:        String,
    isDir:       Bool,
    extension:   String,
    firstLetter: Int,
    fileStat:    sys.FileStat,
    subDirLen:   Int
}
class Folder{
    public function new(){}
    public function traceFolder( path: String ){
        for( file in getFolder( path ) ) Sys.println( '    ' + file.name );
    }
    public function getFolder( path: String ){
        var p           = path;
        var isDir       = sys.FileSystem.isDirectory;
        var stat        = sys.FileSystem.stat;
        var charcode    = StringTools.fastCodeAt;
        var ls          = sys.FileSystem.readDirectory( p );
        var folder      = new Array<FileSpec>();
        var extension:  String;
        folder.push({ name: '<-', isDir: true, extension:'', firstLetter: 0, fileStat: null, subDirLen: 0 });
        for( f in ls ){
             var pf = p + f;
             var hasDir = isDir( pf );
             if( f.substr( 0, 1 ) == '.' ) hasDir = false;
             var len = if( hasDir ){
                 var ls2 = sys.FileSystem.readDirectory( p + '/' + f );
                 ls2.length;
             } else { 0; }
             extension = ( hasDir )? '': getExtension( f );
             folder.push( {  name:           f, 
                             isDir:          hasDir, 
                             extension:      extension,
                             firstLetter:    charcode( f, 0 ),
                             fileStat:       stat( pf ),
                             subDirLen:      len
                             });
        }
        folder.sort(
             function( f1: FileSpec, f2: FileSpec ): Int{
                 if( f1.isDir && !f2.isDir ) return -1;
                 if( !f1.isDir && f2.isDir ) return 1;
                 if( f1.firstLetter > f2.firstLetter ) return 1;
                 if( f1.firstLetter < f2.firstLetter ) return -1;
                 return 0;
             }
        );
        return folder;
    }
    public 
    function traceImages( path: String ){
        var count = 0;
        for( file in getFolder( path ) ){
            switch( file.extension ){
                case 'png':
                    Sys.println( '   ' + file.name );
                    count++;
                case 'bmp':
                    Sys.println( '   ' + file.name );
                    count++;
                case 'gif':
                    Sys.println( '   ' + file.name );
                    count++;
                case _:
                    // ignore
            }
        }
        trace( 'total images: ' + count );
    }
    public
    function getImages( path: String ):Array<ImageSpec> {
        var arrImgSpec = new Array<ImageSpec>();
        var pixels;
        var pathFile: String;
        for( file in getFolder( path ) ){
            pathFile = path + file.name;
            switch( file.extension ){
                case 'png':
                    arrImgSpec.push( { fileSpec: file, pixels: getPNG( pathFile ) } );
                case 'bmp':
                    arrImgSpec.push( { fileSpec: file, pixels: getBMP( pathFile ) } );
                case 'gif':
                    arrImgSpec.push( { fileSpec: file, pixels: getGIF( pathFile ) } );
                case _:
                    // ignore
            }
        }
        return arrImgSpec;
    }
    public
    function getPNG( pathFile: String ){
        return readPNG( loadBinary( pathFile ) );
    }
    public
    function getBMP( pathFile: String ){
        return readBMP( loadBinary( pathFile ) );
    }
    public
    function getGIF( pathFile: String ){
        return readGIF( loadBinary( pathFile ) );
    }
    public 
    function open( fileName: String ): FileOutput {
        return File.write( filePath( fileName ), true );
    }
    public
    function savePNG( pixels: Pixels, fileName: String ){
        Sys.println( 'save png ' + fileName );
        var file = open( fileName );
        var pngWriter = new format.png.Writer( file );
        pixels.convertTo( PixelFormat.ARGB );
        var pngData = format.png.Tools.build32ARGB( pixels.width, pixels.height, pixels.bytes );
        pngWriter.write( pngData );
    }
    public
    function saveBMP( pixels: Pixels, fileName: String ){
        Sys.println( 'save bmp ' + fileName );
        var file = open( fileName );
        var bmpWriter = new format.bmp.Writer( file );
        pixels.convertTo(PixelFormat.ARGB);
        var bmpData = format.bmp.Tools.buildFromARGB( pixels.width, pixels.height, pixels.bytes );
        bmpWriter.write( bmpData );
    }
    public
    function readPNG( input: BytesInput ): Pixels {
        var pngReader               = new format.png.Reader( input );
        var data: format.png.Data   = pngReader.read();
        var pixels: Pixels          = data;
        return pixels;
    }
    public
    function readBMP( input: BytesInput ): Pixels {
        var bmpReader               = new format.bmp.Reader( input );
        var data: format.bmp.Data   = bmpReader.read();
        var pixels: Pixels          = data;
        return pixels;
    }
    public
    function readGIF( input: BytesInput ): Pixels {
        var gifReader               = new format.gif.Reader( input );
        var data: format.gif.Data   = gifReader.read();
        var pixels: Pixels          = Pixels.fromGIFData( data
            , Std.random(format.gif.Tools.framesCount(data)), Std.random(2) == 0 ? true : false);
        return pixels;
    }
    public
    function getExtension( str: String ){
        var out = '';
        var count = 0;
        for( i in 0...10 ){
            var j = ( i + 1 );
            if( str.charCodeAt( str.length - j ) == '.'.code ){
                out = str.substr( -i ).toLowerCase();
                break;
            }
            count++;
        }
        if( count == 10 ) out = '';
        return out;
    }
    public
    function createDirectory( fileName: String ){
        Sys.println( 'create directory ' + fileName );
        FileSystem.createDirectory( filePath( fileName ) );
    }
    public
    function deleteDirectory( fileName: String ){
        Sys.println( 'delete directory ' + fileName );
        var path = filePath( fileName );
        if( FileSystem.exists( path ) ) {
            var f = getFolder( fileName + '/' );
            for( file in f ){
                Sys.println( 'deleting file ' + file.name );
                if( !file.isDir && file.name != '<-' ) FileSystem.deleteFile( path + '/' + file.name );
            }
            FileSystem.deleteDirectory( path );
        }
    }
    public 
    function saveText( fileName: String, str: String ){
        Sys.println( 'save text ' + fileName );
        sys.io.File.saveContent( filePath( fileName ), str );
    }
    public 
    function loadText( fileName: String ){
        Sys.println( 'load text ' + fileName );
        return File.getContent( filePath( fileName ) );
    }
    public inline
    function loadBinary( fileName: String ): BytesInput {
        Sys.println( 'load binary ' + fileName );
        return new BytesInput( File.getBytes( filePath( fileName ) ) );
    }
    public
    function filePath( fname: String ){
        return Path.join( [ dir, fname ] );
    }
    public var dir( get, never ): String;
    function get_dir(): String {
        #if neko
        var dir = Path.directory( Module.local().name );
        #else
        var dir = Path.directory( Sys.executablePath() );
        #end
        return dir;
    }
}