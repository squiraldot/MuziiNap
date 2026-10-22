class Thumbnail {
  Thumbnail(this._url);
  final String _url;
  String sizewith(int size) => (_url.contains("-rj"))
      ? "${_url.split("=")[0]}=w$size-h$size-l90-rj"
      : (_url.contains("=s"))
          ? "${_url.split("=s")[0]}=s$size"
          : (_url.contains("i.yti") && size >= 600)
              ? url.replaceFirst("sddefault", "maxresdefault")
              : url;
  String get url => _url;
  String get high => sizewith(400); //450
  String get medium => sizewith(250); //350
  String get low => sizewith(150);
  String get extraHigh => sizewith(600);
}
