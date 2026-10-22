import '../services/stream_service.dart'show Audio;

class HMStreamingData {
  final bool playable;
  final String statusMSG;
  final Audio? lowQualityAudio;
  final Audio? highQualityAudio;
  final Map<String, String>? streamHeaders;
  int qualityIndex = 1;
  HMStreamingData({
    required this.playable,
    required this.statusMSG,
    this.lowQualityAudio,
    this.highQualityAudio,
    this.streamHeaders,
  });

  setQualityIndex(int index) {
    qualityIndex = index;
  }

  Audio? get audio => qualityIndex == 0 ? lowQualityAudio : highQualityAudio;

  factory HMStreamingData.fromJson(json) {
    if(!json['playable']) {
      return HMStreamingData(
        playable: false,
        statusMSG: json['statusMSG'],
      );
    }
    final lowQualityAudio = Audio.fromJson(json['lowQualityAudio']);
    final highQualityAudio = Audio.fromJson(json['highQualityAudio']);
    final headersMap = json['streamHeaders'] != null 
        ? Map<String, String>.from(json['streamHeaders']) 
        : null;
        
    return HMStreamingData(
        playable: json['playable'],
        statusMSG: json['statusMSG'],
        lowQualityAudio: lowQualityAudio,
        highQualityAudio: highQualityAudio,
        streamHeaders: headersMap,
    );
  }

  Map<String, dynamic> toJson() => {
        "playable": playable,
        "statusMSG": statusMSG,
        "lowQualityAudio": lowQualityAudio?.toJson(),
        "highQualityAudio": highQualityAudio?.toJson(),
        if (streamHeaders != null) "streamHeaders": streamHeaders,
      };
}
