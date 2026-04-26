import 'dart:convert';

import 'package:dowplay/EpisodeMedia.dart';
import 'package:dowplay/MovieMedia.dart';
import 'package:dowplay/DownloadMovie.dart';
import 'package:dowplay/DownloadEpisode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:dowplay/dowplay.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _dowplayPlugin = Dowplay();

  final String accessToken =
      "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJhdWQiOiI5IiwianRpIjoiZTdlNzUwYTE2Njc4N2Q3ZGM3OGMxMTRmZGUzYWE4NDczYTlkOGEzYjQxYTIwYWIzZjhjYzhjYjM0NDU3YmQ4ZTk0NjI0MjU5NWI3MGZhYWYiLCJpYXQiOjE2ODI5NjU4OTAuNzk1MjA2LCJuYmYiOjE2ODI5NjU4OTAuNzk1MjEsImV4cCI6MTcxNDU4ODI5MC43ODgyODksInN1YiI6IjI0NTM5NCIsInNjb3BlcyI6W119.lACpnX8ajL8rPq8GfN1tUnOLGSn8nUBAnIXEY2dZCduZ1eoIlrz_g4iTIfjmgF4Mu7vFqPU8DINhifvNifUDP8MjtLqG_j2iAjq9jOf24XnuGy8DEp-qiV5wQJK1xBJE93fiPe38DPUXGfoZws42YjnJT-nSgGgWb2EZCyYqUh4x3V_yLbNtNotpbBxQA55tw53D-ibij357D-V0-ZBhfDQ6YtN066IUVHhC8U33X-Akvdwdb6i_1eI2IwaxWVzPqAp5-Xz77hNtIx1iu7STrAEoerQFiLKO1kGM3lh35VUIN_UQkMo4URwU0QMWlfDDYgrRlDEngdodHmYNbwQYe6iNQmYXAiK4DCMqnOD2OEud3h0MLT7lg-ZWpOLJS-z1ZrOnfU6APxq-zOeS1__tFGrM8rPe6ROl855ZCosCLhAnxbXkuHzB_8XozEwE64QH3KNTRp5LdbCq3QRIDrJ8sWGz-VnAN4N0DcHuXcfi6aQN_itlY7fqsg2EbZzf8O026kyi7EIUWRAfekRCLbXS5Ot_00bEWYWx5T4DO9CO-e7oKWx0bucJptHhAg80bqdY6cK3uQ9Ai_Upk-3qacDi5y_UU4lU8GglLp7xDGFV0dfEAd3mMK93wHeKiKKA5hb3DaEhdDwP8QBne5VVAKKXJPihkglmE_IgtSFd23J6vNw";
  late Map<String, dynamic> movieObject;
  late MovieMedia movieMedia;
  late DownloadMovie downloadMovie;

  List _downloadsList = [];

  @override
  void initState() {
    super.initState();
    movieObject = {
      "id": 377530,
      "title": "The Simpsons in Plusaversary",
      "description":
          "يتبع The Simpsons أثناء استضافتهم لحفلة Disney Day مع الأصدقاء من جميع أنحاء الخدمة ، وكل شخص موجود في القائمة - باستثناء Homer\r\n\r\n\r\nFollows The Simpsons\" as they host a Disney+ Day party with friends from across the service, everyone is on the list - except Homer.",
      "download_url":
          "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/The.Simpsons.in.Plusaversary.2021.1080.mp4?md5=QA-5PWsq9OIEaa0EM79p9A&expires=1678670074",
      "hd_url":
          "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Klaus.2019.720p.mp4?md5=ipbkWahE7MGcaEAdHHRS8g&expires=1678668998",
      "trailer_url": null,
      "media_url":
          "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Klaus.2019.1080p.mp4?md5=shMoxWUw5sX8KK6q-QH16w&expires=1678668998",
      "duration": "5m",
      "language": "English",
      "translation": "العربية",
      "year": "2021",
      "cover_photo":
          "https://thekee-m.gcdn.co/images06012022/uploads/media/movies/covers/2022-10-16/w0wGiEtcApEObeNk.png",
      "poster_photo":
          "https://thekee-m.gcdn.co/images06012022/uploads/media/movies/posters/2021-11-13/cOKqU1ftE6HQbxv6.jpg",
      "tags": [
        {"id": 57, "title": "Kids"},
        {"id": 2, "title": "Comedy"},
        {"id": 28, "title": "Animation"},
        {"id": 64, "title": "English"}
      ],
      "actors": [
        {
          "id": 6019,
          "name": "Dan Castellaneta",
          "image":
              "https://thekee-m.gcdn.co/images06012022/uploads/actors/6019/818ABOIVFVFMolTI.png"
        },
        {
          "id": 25326,
          "name": "Yeardley Smith",
          "image":
              "https://thekee-m.gcdn.co/images06012022/uploads/actors/2021-11-13/X477M3hjEfXSv7Um.png"
        },
        {
          "id": 10955,
          "name": "Nancy Cartwright",
          "image":
              "https://thekee-m.gcdn.co/images06012022/uploads/actors/10955/kNrav6MXJYTdvQbg.png"
        },
        {
          "id": 13727,
          "name": "Hank Azaria",
          "image":
              "https://thekee-m.gcdn.co/images06012022/uploads/actors/13727/ae18InPvKS9MXDLC.png"
        },
        {
          "id": 25327,
          "name": "Tress MacNeille",
          "image":
              "https://thekee-m.gcdn.co/images06012022/uploads/actors/2021-11-13/47A9foEusHXvvWv2.png"
        }
      ],
      "director_info": {
        "id": 6593,
        "name": "David Silverman",
        "image":
            "https://thekee-m.gcdn.co/images06012022/uploads/directors/2022-10-16/z16camhTHPAt1JMh.png"
      },
      "is_favourite": false,
      "imdb_rating": "5.6",
      "imdb_certificate": null,
      "watching": {
        "current_time": "3121",
        "duration": "7576",
        "title": "ملاذكرد 1071 - Malazgirt 1071",
        "order": 0,
        "description":
            "في العام 1071، يلتقي الجيشان السلجوقي والبيزنطي في ميدان المعركة ليخوضا مواجهة دامية في هذه اللحظة المفصلية من تاريخ الإمبراطورية البيزنطية.\r\n\r\nThe story of the war, which is the beginning of the history of Turks in Anatolia.",
        "last_media_id": 380988,
        "1080_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Klaus.2019.1080p.mp4?md5=Jr7WQNNScUtlCM1AcjCN2Q&expires=1678754308",
        "720_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Klaus.2019.720p.mp4?md5=JSkSnlOwvrIqbPwlC8vekA&expires=1678754308",
        "continue_type": null,
        "next_type": null,
        "next_episode": null
      }
    };
    movieMedia = MovieMedia(
        title: "The Simpsons in Plusaversary",
        subTitle: "",
        url:
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/The.Simpsons.in.Plusaversary.2021.1080.mp4?md5=QA-5PWsq9OIEaa0EM79p9A&expires=1678670074",
        mediaId: "377530",
        mediaType: "movie",
        userId: "245394",
        profileId: "562674",
        token: accessToken,
        apiBaseUrl: "https://v4.kaayapp.com/api",
        lang: "ar",
        startAt: 3,
        info: movieObject,
        isDownloadEnabled: false);
    downloadMovie = DownloadMovie(
        title: "The Simpsons in Plusaversary",
        subTitle: "",
        url:
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/The.Simpsons.in.Plusaversary.2021.1080.mp4?md5=QA-5PWsq9OIEaa0EM79p9A&expires=1678670074",
        mediaId: "377530",
        mediaType: "movie",
        userId: "245394",
        profileId: "562674",
        info: movieObject,
    isDownloadEnabled: false);

    // Should be called on the app start
    config();
  }

  config() async {
    bool result;
    try {
      result = await _dowplayPlugin.config({
            "user_id": "245394",
            "profile_id": "562674",
            "lang": "ar",
            "access_token": accessToken
          }) ??
          false;
      if (kDebugMode) {
        print("result : $result");
      }
    } on PlatformException {
      result = false;
    }
  }

  Future<void> playEpisode() async {
    // Will be Episode Item model which you need to start
    Map<String, dynamic> episodeToStart = {
      "id": 64864,
      "title": "Episode 2",
      "order": "2",
      "poster_photo":
          "https://thekee-m.gcdn.co/images06012022/uploads/media/series/seasons/posters/2020-07-01/ZMx47Bf3sO03FprZ.jpg",
      "duration": "10 min",
      "download_url":
          "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/02.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
      "hd_url":
          "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/02.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
      "trailer_url": null,
      "media_url":
          "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/02.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
      "created_at": "2020-07-01 13:27:14",
      "release_date": "2020-07-01 00:00:00",
      "watching": null
    };

    List<Map<String, dynamic>> seasonEpisodes = [
      {
        "id": 64863,
        "title": "Episode 1",
        "order": "1",
        "poster_photo":
            "https://thekee-m.gcdn.co/images06012022/uploads/media/series/seasons/posters/2020-07-01/ZMx47Bf3sO03FprZ.jpg",
        "duration": "10 min",
        "download_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/01.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
        "hd_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/01.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
        "trailer_url": null,
        "media_url":
            /*"https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/01.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892"*/
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Klaus.2019.1080pAr.mp4",
        "created_at": "2020-07-01 13:27:14",
        "release_date": "2020-07-01 00:00:00",
        "watching": {"current_time": "3000", "duration": "1380"}
      },
      {
        "id": 64864,
        "title": "Episode 2",
        "order": "2",
        "poster_photo":
            "https://thekee-m.gcdn.co/images06012022/uploads/media/series/seasons/posters/2020-07-01/ZMx47Bf3sO03FprZ.jpg",
        "duration": "10 min",
        "download_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/02.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
        "hd_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/02.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
        "trailer_url": null,
        "media_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/02.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
        "created_at": "2020-07-01 13:27:14",
        "release_date": "2020-07-01 00:00:00",
        "watching": {"current_time": "25", "duration": "60"}
      },
      {
        "id": 64865,
        "title": "Episode 3",
        "order": "3",
        "poster_photo":
            "https://thekee-m.gcdn.co/images06012022/uploads/media/series/seasons/posters/2020-07-01/ZMx47Bf3sO03FprZ.jpg",
        "duration": "10 min",
        "download_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/03.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
        "hd_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Drama/The.Irishman.2019.720p.V1.mp4?md5=ZF34W64FwMoh3vIlOnfNXQ&expires=1685804927",
        "trailer_url": null,
        "media_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Drama/The.Irishman.2019.720p.V1.mp4?md5=ZF34W64FwMoh3vIlOnfNXQ&expires=1685804927",
        "created_at": "2020-07-01 13:27:14",
        "release_date": "2020-07-01 00:00:00",
        "watching": null
      },
      {
        "id": 64866,
        "title": "Episode 4",
        "order": "4",
        "poster_photo":
            "https://thekee-m.gcdn.co/images06012022/uploads/media/series/seasons/posters/2020-07-01/ZMx47Bf3sO03FprZ.jpg",
        "duration": "10 min",
        "download_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/04.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
        "hd_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/04.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
        "trailer_url": null,
        "media_url":
            "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/04.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
        "created_at": "2020-07-01 13:27:14",
        "release_date": "2020-07-01 00:00:00",
        "watching": {"current_time": "30", "duration": "60"}
      }
    ];

    Map<String, dynamic> itemIds = {
      "season_id": "3236",
      "tv_show_id": "1532",
    };

    Map<String, dynamic> mediaGroup = {
      "tv_show": {
        "id": 1532,
        "title": "Tom and Jerry",
        "description":
            "المسلسل الكارتونى المحبب للجميع و اشهر المعارك بين القط و الفار",
        "trailer_url": null,
        "language": "English",
        "translation": "-",
        "start_year": "1967",
        "end_year": "1967",
        "cover_photo": null,
        "poster_photo":
            "https://thekee-m.gcdn.co/images06012022/uploads/media/series/posters/2020-07-01/UJP1JIdmnijsHDX2.jpg",
        "seasons": [
          {
            "id": 3236,
            "season_id": 3747,
            "poster_photo":
                "https://thekee-m.gcdn.co/images06012022/uploads/media/series/seasons/posters/2020-07-01/ZMx47Bf3sO03FprZ.jpg",
            "cover_photo": null,
            "trailer_url": null,
            "season_number": "1",
            "title": "Tom and Jerry S01"
          }
        ],
        "tags": [
          {"id": 57, "title": "Kids"},
          {"id": 28, "title": "Animation"},
          {"id": 64, "title": "English"}
        ],
        "actors": [],
        "director_info": null,
        "is_favourite": false,
        "imdb_rating": null,
        "imdb_certificate": null,
        "last_watching": null,
        "last_watching_season_id": null
      },
      "season": {
        "id": 3236,
        "season_id": 3747,
        "poster_photo":
            "https://thekee-m.gcdn.co/images06012022/uploads/media/series/seasons/posters/2020-07-01/ZMx47Bf3sO03FprZ.jpg",
        "cover_photo": null,
        "trailer_url": null,
        "season_number": "1",
        "title": "Tom and Jerry S01"
      },
      "items_ids": itemIds,
      "episodes": seasonEpisodes
    };

    EpisodeMedia media = EpisodeMedia(
        mediaType: "series",
        userId: "245394",
        profileId: "562674",
        token: accessToken,
        apiBaseUrl: "https://v4.kaayapp.com/api",
        lang: "ar",
        startAt: 3,
        info: episodeToStart,
        mediaGroup: mediaGroup,
    isDownloadEnabled: false);
    dynamic result = await invokePlayEpisode(media);
    if (kDebugMode) {
      printWrapped("Play episode result : $result");
    }
  }

  Future<void> playMovie() async {
    dynamic result = await invokePlayMovie(movieMedia);
    if (kDebugMode) {
      printWrapped("Play movie result : $result");
    }
  }

  Future<dynamic> getDownloadsList() async {
    dynamic result = await invokeGetDownloadsList();
    if (kDebugMode) {
      List<dynamic> downloads = List.from(result as Iterable);
      if (mounted) {
        setState(() {
          _downloadsList = downloads;
        });
      }
      printWrapped(
          "Downloads list [${downloads.length}] : ${jsonEncode(downloads)}");
    }
  }

  Future<dynamic> getDownloadMovie() async {
    dynamic result = await invokeGetDownloadMovie();
    if (kDebugMode) {
      printWrapped("Returned Movie  ${jsonEncode(result)}");
    }
  }

  Future<dynamic> invokeGetDownloadMovie() async {
    dynamic result;
    try {
      result =
          await _dowplayPlugin.getDownloadMovie(movieObject['id'].toString());
    } on PlatformException {
      result = false;
    }
    return result;
  }

  Future<dynamic> getDownloadEpisode() async {
    dynamic result = await invokeGetDownloadEpisode();
    if (kDebugMode) {
      printWrapped("Returned Episode  ${jsonEncode(result)}");
    }
  }

  Future<dynamic> invokeGetDownloadEpisode() async {
    dynamic result;
    try {
      result = await _dowplayPlugin.getDownloadEpisode(
        "64864", //episond
        "1532", //tvshow
        "3236", //season
      );
    } on PlatformException {
      result = false;
    }
    return result;
  }

  Future<dynamic> getTvShowSeasonsDownloadList() async {
    dynamic result = await invokeGetTvShowSeasonsDownloadList();
    if (kDebugMode) {
      List<dynamic> downloads = List.from(result as Iterable);
      if (mounted) {
        setState(() {
          _downloadsList = downloads;
        });
      }
      printWrapped(
          "TvShow Seasons Downloads list [${downloads.length}] : ${jsonEncode(downloads)}");
    }
  }

  Future<dynamic> getSeasonEpisodesDownloadList() async {
    dynamic result = await invokeGetSeasonEpisodesDownloadList();
    if (kDebugMode) {
      List<dynamic> downloads = List.from(result as Iterable);
      if (mounted) {
        setState(() {
          _downloadsList = downloads;
        });
      }
      printWrapped(
          "TvShow Seasons Downloads list [${downloads.length}] : ${jsonEncode(downloads)}");
    }
  }

  Future<dynamic> startDownloadMovie() async {
    String type = "movie";

    dynamic result = await invokeStartDownloadMovie(type, downloadMovie);
    print("result is $result");
    if (kDebugMode) {
      List<dynamic> downloads = List.from(result as Iterable);
      if (mounted) {
        setState(() {
          _downloadsList = downloads;
        });
      }
      // printWrapped(
      //     "Downloads list [${downloads.length}] : ${jsonEncode(downloads)}");
    }
  }

  Future<dynamic> startDownloadEpisode() async {
    String type = "series";
    // Will be Episode Item model which you need to download
    Map<String, dynamic> episodeToDownload = {
      "id": 64864,
      "title": "Episode 2",
      "order": "2",
      "poster_photo":
          "https://thekee-m.gcdn.co/images06012022/uploads/media/series/seasons/posters/2020-07-01/ZMx47Bf3sO03FprZ.jpg",
      "duration": "10 min",
      "download_url":
          "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/02.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
      "hd_url":
          "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/02.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
      "trailer_url": null,
      "media_url":
          "https://s3.eu-central-1.wasabisys.com/bu26032021/m-159n/English/Animation&Family/Tom.and.Jerry.1965/02.mp4?md5=eCp0VmIS_doipZ6lGVxwVg&expires=1678550892",
      "created_at": "2020-07-01 13:27:14",
      "release_date": "2020-07-01 00:00:00",
      "watching": null
    };

    Map<String, dynamic> itemIds = {
      "season_id": "3236",
      "tv_show_id": "1532",
    };
    Map<String, dynamic> mediaGroup = {
      "tv_show": {
        "id": 1532,
        "title": "Tom and Jerry",
        "description":
            "المسلسل الكارتونى المحبب للجميع و اشهر المعارك بين القط و الفار",
        "trailer_url": null,
        "language": "English",
        "translation": "-",
        "start_year": "1967",
        "end_year": "1967",
        "cover_photo": null,
        "poster_photo":
            "https://thekee-m.gcdn.co/images06012022/uploads/media/series/posters/2020-07-01/UJP1JIdmnijsHDX2.jpg",
        "seasons": [
          {
            "id": 3236,
            "season_id": 3747,
            "poster_photo":
                "https://thekee-m.gcdn.co/images06012022/uploads/media/series/seasons/posters/2020-07-01/ZMx47Bf3sO03FprZ.jpg",
            "cover_photo": null,
            "trailer_url": null,
            "season_number": "1",
            "title": "Tom and Jerry S01"
          }
        ],
        "tags": [
          {"id": 57, "title": "Kids"},
          {"id": 28, "title": "Animation"},
          {"id": 64, "title": "English"}
        ],
        "actors": [],
        "director_info": null,
        "is_favourite": false,
        "imdb_rating": null,
        "imdb_certificate": null,
        "last_watching": null,
        "last_watching_season_id": null
      },
      "season": {
        "id": 3236,
        "season_id": 3747,
        "poster_photo":
            "https://thekee-m.gcdn.co/images06012022/uploads/media/series/seasons/posters/2020-07-01/ZMx47Bf3sO03FprZ.jpg",
        "cover_photo": null,
        "trailer_url": null,
        "season_number": "1",
        "title": "Tom and Jerry S01"
      },
      "items_ids": itemIds,
    };

    DownloadEpisode media = DownloadEpisode(
        mediaType: "series",
        userId: "245394",
        profileId: "562674",
        info: episodeToDownload,
        mediaGroup: mediaGroup,
        isDownloadEnabled: false);

    dynamic result = await invokeStartDownloadEpisode(type, media);
    List<dynamic> downloads = List.from(result as Iterable);
    if (mounted) {
      setState(() {
        _downloadsList = downloads;
      });
      printWrapped(
          "Downloads list [${downloads.length}] : ${jsonEncode(downloads)}");
    }
  }

  Future<dynamic> pauseDownload() async {
    dynamic result =
        await invokePauseDownload(movieMedia.mediaId, movieMedia.mediaType);
    List<dynamic> downloads = List.from(result as Iterable);
    if (mounted) {
      setState(() {
        _downloadsList = downloads;
      });
    }
    // printWrapped(
    //     "Downloads list [${downloads.length}] : ${jsonEncode(downloads)}");
  }

  Future<dynamic> resumeDownload() async {
    dynamic result =
        await invokeResumeDownload(movieMedia.mediaId, movieMedia.mediaType);
    if (kDebugMode) {
      List<dynamic> downloads = List.from(result as Iterable);
      if (mounted) {
        setState(() {
          _downloadsList = downloads;
        });
      }
      // printWrapped(
      //     "Downloads list [${downloads.length}] : ${jsonEncode(downloads)}");
    }
  }

  Future<dynamic> cancelDownload() async {
    dynamic result =
        await invokeCancelDownload("64864", "series ", "1532", "3236");
    if (kDebugMode) {
      List<dynamic> downloads = List.from(result as Iterable);
      if (mounted) {
        setState(() {
          _downloadsList = downloads;
        });
      }
      // printWrapped(
      //     "Downloads list [${downloads.length}] : ${jsonEncode(downloads)}");
    }
  }

  Future<dynamic> invokePlayEpisode(EpisodeMedia media) async {
    dynamic result;
    try {
      result = await _dowplayPlugin.playEpisode(media) ?? false;
      if (kDebugMode) {
        print("result : $result");
      }
    } on PlatformException {
      result = false;
    }
    return result;
  }

  Future<dynamic> invokePlayMovie(MovieMedia media) async {
    dynamic result;
    try {
      result = await _dowplayPlugin.playMovie(media) ?? false;
      if (kDebugMode) {
        print("result : $result");
      }
    } on PlatformException {
      result = false;
    }
    return result;
  }

  Future<dynamic> invokeGetDownloadsList() async {
    dynamic result;
    try {
      result = await _dowplayPlugin.getDownloadsList();
    } on PlatformException {
      result = false;
    }
    return result;
  }

  Future<dynamic> invokeGetTvShowSeasonsDownloadList() async {
    dynamic result;
    try {
      result = await _dowplayPlugin.getTvShowSeasonsDownloadList({
        "tvshow_id": "1532" // should be string
      });
    } on PlatformException {
      result = false;
    }
    return result;
  }

  Future<dynamic> invokeGetSeasonEpisodesDownloadList() async {
    dynamic result;
    try {
      result = await _dowplayPlugin.getSeasonEpisodesDownloadList({
        "tvshow_id": "1532", // should be string,
        "season_id": "3236"
      });
    } on PlatformException {
      result = false;
    }
    return result;
  }

  Future<dynamic> invokeStartDownloadMovie(
      String type, DownloadMovie media) async {
    Map<String, dynamic> item = {
      "type": type,
      "media": downloadMovie,
    };
    dynamic result;
    item['media'] = (item['media'] as DownloadMovie).toJson();
    try {
      result = await _dowplayPlugin.startDownloadMovie(item['media']);
    } on PlatformException {
      result = false;
    }
    return result;
  }

  Future<dynamic> invokeStartDownloadEpisode(
      String type, DownloadEpisode media) async {
    Map<String, dynamic> item = {
      "type": type,
      "media": media,
    };
    dynamic result;
    item['media'] = (item['media'] as DownloadEpisode).toJson();
    try {
      result = await _dowplayPlugin.startDownloadEpisode(item['media']);
    } on PlatformException {
      result = false;
    }
    return result;
  }

  Future<dynamic> invokePauseDownload(String mediaId, String mediaType) async {
    dynamic result;
    try {
      result = await _dowplayPlugin.pauseDownload(mediaId, mediaType);
    } on PlatformException {
      result = false;
    }
    return result;
  }

  Future<dynamic> invokeResumeDownload(String mediaId, String mediaType) async {
    dynamic result;
    try {
      result = await _dowplayPlugin.resumeDownload(mediaId, mediaType);
    } on PlatformException {
      result = false;
    }
    return result;
  }

  Future<dynamic> invokeCancelDownload(String mediaId, String mediaType,
      dynamic tvShowId, dynamic seasonId) async {
    dynamic result;
    try {
      result = await _dowplayPlugin.cancelDownload(
          mediaId, mediaType, tvShowId, seasonId);
    } on PlatformException {
      result = false;
    }
    return result;
  }

  void printWrapped(String text) {
    final pattern = RegExp('.{1,800}'); // 800 is the size of each chunk
    pattern.allMatches(text).forEach((match) => print(match.group(0)));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: playEpisode,
                  child: const Text("Play Episode"),
                ),
                ElevatedButton(
                  onPressed: playMovie,
                  child: const Text("Play Movie"),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 24.0, horizontal: 32),
                  child: SizedBox(
                    height: 2,
                    child: Container(
                      color: Colors.black26,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: getDownloadsList,
                  child: const Text("Print Downloads List"),
                ),
                Visibility(
                  visible: _downloadsList.isNotEmpty,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _downloadsList.length,
                      itemBuilder: (context, index) {
                        return Text(
                            "Count::: ${_downloadsList.length}+ ${_downloadsList[index]}"
                            // "[${index + 1}]-> (${_downloadsList[index]['mediaType']}) : ${_downloadsList[index]['mediaType'] == "movie" ? _downloadsList[index]['object']['title'] : _downloadsList[index]['object']['info']['title']} - ${_downloadsList[index]['status']} - ${_downloadsList[index]['progress']}",
                            );
                      },
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: getTvShowSeasonsDownloadList,
                  child: const Text("Print TvShow Seasons Downloads List"),
                ),
                ElevatedButton(
                  onPressed: getSeasonEpisodesDownloadList,
                  child: const Text("Print Season Episodes Downloads List"),
                ),
                ElevatedButton(
                  onPressed: startDownloadMovie,
                  child: const Text("Start Download Movie"),
                ),
                ElevatedButton(
                  onPressed: startDownloadEpisode,
                  child: const Text("Start Download Episode"),
                ),
                ElevatedButton(
                  onPressed: pauseDownload,
                  child: const Text("Pause Download"),
                ),
                ElevatedButton(
                  onPressed: resumeDownload,
                  child: const Text("Resume Download Movie"),
                ),
                ElevatedButton(
                  onPressed: cancelDownload,
                  child: const Text("Cancel Download Movie"),
                ),
                ElevatedButton(
                  onPressed: getDownloadMovie,
                  child: const Text("Get Download Movie"),
                ),
                ElevatedButton(
                  onPressed: getDownloadEpisode,
                  child: const Text("Get Download Episode"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
