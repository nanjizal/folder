package folder;
import sys.FileSystem;
class PathInfo{
    public var path:    String = './';
    public var full:    String;
    public var parent:  String;
    var forwardSlash: Int = 47;
    public
    function new( path_: String ){
        changePath( path_ );
    }
    public
    function changePath( path_: String ){
        if( path == path_  && full != null ) return;
        path = path_;
        var charcode = StringTools.fastCodeAt;
        full = sys.FileSystem.fullPath( path );
        var len = full.length;
        while( len > 0 && charcode( full, len-- ) != fowardSlash ){}
        parent = full.substr( 0, len + 1 ) + '/';
    }
    public
    function tracePaths(){
        trace( 'path ' + path );
        trace( 'full ' + full );
        trace( 'parent ' + parent );
    }
}
