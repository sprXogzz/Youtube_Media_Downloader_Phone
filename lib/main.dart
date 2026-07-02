import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const YoutubeMediaDownloader());
}

class YoutubeMediaDownloader extends StatelessWidget {
  const YoutubeMediaDownloader({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Youtube Media Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.redAccent,
        colorScheme: const ColorScheme.dark(
          primary: Colors.redAccent,
          secondary: Colors.red,
        ),
      ),
      home: const AnaSayfa(),
    );
  }
}

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  final TextEditingController _linkDenetleyici = TextEditingController();
  bool _indirmeBasladiMi = false;
  double _indirmeYuzdesi = 0.0;
  String _durumMesaji = "İndirmek istediğiniz YouTube linkini yapıştırın";
  String _secilenFormat = "MP4";
  String _secilenKalite = "720p"; 
  final List<String> _kaliteListesi = ["1080p", "720p", "480p", "360p"];

  @override
  void initState() {
    super.initState();
    // Uygulama açılır açılmaz tüm telefonlarda çalışacak izin mekanizmasını tetikliyoruz
    _gelismisDepolamaIzniniIste();
  }

  // Tüm Android sürümlerinde (Eski ve Yeni) çalışan akıllı izin fonksiyonu
  Future<void> _gelismisDepolamaIzniniIste() async {
    // android 11 için bura izin
    if (await Permission.manageExternalStorage.request().isGranted) {
      return; // İzin verildiyse fonksiyonu bitir
    }

    // android 10 ve altı cihazlar için bura izin
    
    Map<Permission, PermissionStatus> izinler = await [
      Permission.storage,
      Permission.videos,
      Permission.audio,
    ].request();

    // izinlerden biri geçtiği an programı çalıştır
    if (izinler[Permission.storage]!.isGranted || izinler[Permission.videos]!.isGranted) {
      return;
    } else {
      setState(() {
        _durumMesaji = " Uyarı: Medyaları kaydedebilmek için depolama izni vermelisiniz!";
      });
    }
  }

  Future<void> _medyayiIndir() async {
    final String videoLinki = _linkDenetleyici.text.trim();

    if (videoLinki.isEmpty) {
      setState(() {
        _durumMesaji = "Lütfen geçerli bir link girin!";
      });
      return;
    }

    // indirme başlamadan önce izinleri tekrar check et
    if (!await Permission.storage.isGranted && !await Permission.manageExternalStorage.isGranted) {
      await _gelismisDepolamaIzniniIste();
    }

    setState(() {
      _indirmeBasladiMi = true;
      _indirmeYuzdesi = 0.0;
      _durumMesaji = "YouTube'a bağlanılıyor...";
    });

    final yt.YoutubeExplode youtubeIstemcisi = yt.YoutubeExplode();

    try {
      final yt.VideoId videoId = yt.VideoId(videoLinki);
      
      setState(() {
        _durumMesaji = "Video bilgileri ve kaliteler analiz ediliyor...";
      });

      final yt.StreamManifest akisManifestosu = await youtubeIstemcisi.videos.streams.getManifest(videoId);
      final yt.Video videoDetaylari = await youtubeIstemcisi.videos.get(videoId);

      dynamic secilenAkis;

      if (_secilenFormat == "MP4") {
        var videoAkislari = akisManifestosu.muxed; 
        
        if (_secilenKalite == "1080p") {
          secilenAkis = videoAkislari.withHighestBitrate();
        } else if (_secilenKalite == "720p") {
          secilenAkis = videoAkislari.firstWhere(
            (e) => e.videoQuality.toString().contains('hd720'), 
            orElse: () => videoAkislari.withHighestBitrate()
          );
        } else if (_secilenKalite == "480p") {
          secilenAkis = videoAkislari.firstWhere(
            (e) => e.videoQuality.toString().contains('large480'), 
            orElse: () => videoAkislari.firstWhere(
              (e) => e.videoQuality.toString().contains('medium360'), 
              orElse: () => videoAkislari.withHighestBitrate()
            )
          );
        } else {
          secilenAkis = videoAkislari.firstWhere(
            (e) => e.videoQuality.toString().contains('medium360'), 
            orElse: () => videoAkislari.withHighestBitrate()
          );
        }
      } else {
        secilenAkis = akisManifestosu.audio.withHighestBitrate();
      }

      if (secilenAkis == null) {
        throw Exception("İtenilen formatta veya kalitede uygun akış bulunamadı.");
      }

      Directory? indirilenlerKlasoru = Directory('/storage/emulated/0/Download');
      if (!await indirilenlerKlasoru.exists()) {
        indirilenlerKlasoru = await getExternalStorageDirectory();
      }

      final String temizDosyaAdi = videoDetaylari.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
      final String dosyaUzantisi = _secilenFormat == "MP4" ? "mp4" : "mp3";
      final String tamDosyaYolu = "${indirilenlerKlasoru!.path}/$temizDosyaAdi.$dosyaUzantisi";

      final Stream<List<int>> indirmeAkisi = youtubeIstemcisi.videos.streams.get(secilenAkis);
      final File dosya = File(tamDosyaYolu);
      final IOSink dosyaYazici = dosya.openWrite();

      // progress bar için boyut hesaplıyo
      final int toplamBoyut = secilenAkis.size.totalBytes;
      int indirilenBoyut = 0;

      await for (var veriParcacigi in indirmeAkisi) {
        indirilenBoyut += veriParcacigi.length;
        dosyaYazici.add(veriParcacigi);

        setState(() {
          _indirmeYuzdesi = indirilenBoyut / toplamBoyut;
          _durumMesaji = "İndiriliyor: %${(_indirmeYuzdesi * 100).toStringAsFixed(1)}";
        });
      }

      await dosyaYazici.flush();
      await dosyaYazici.close();
    // indirme tamamlandığında alert at
      setState(() {
        _indirmeBasladiMi = false;
        _durumMesaji = "🏆 Başarıyla İndirildi!\nKonum: Telefon hafızası / Download";
      });

    } catch (hata) {
      setState(() {
        _indirmeBasladiMi = false;
        _durumMesaji = "Bir hata oluştu: ${hata.toString()}";
      });
    } finally {
      youtubeIstemcisi.close();
    }
  }
  // ui burası
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Youtube Media Downloader'), 
        centerTitle: true,
        backgroundColor: const Color(0xFF1F1F1F),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    Image.network(
                      'ogiyticon.png',
                      height: 120,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.video_library_rounded, size: 80, color: Colors.redAccent);
                      },
                    ),
                    const SizedBox(height: 30),

                    TextField(
                      controller: _linkDenetleyici,
                      decoration: InputDecoration(
                        hintText: 'https://www.youtube.com/watch?...',
                        labelText: 'YouTube Video Linki',
                        prefixIcon: const Icon(Icons.link, color: Colors.redAccent),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text('🎬 MP4 (Video)'),
                          selected: _secilenFormat == "MP4",
                          selectedColor: Colors.redAccent.withOpacity(0.3),
                          onSelected: (bool secildi) {
                            if (secildi) setState(() => _secilenFormat = "MP4");
                          },
                        ),
                        const SizedBox(width: 20),
                        ChoiceChip(
                          label: const Text('🎵 MP3 (Ses)'),
                          selected: _secilenFormat == "MP3",
                          selectedColor: Colors.redAccent.withOpacity(0.3),
                          onSelected: (bool secildi) {
                            if (secildi) setState(() => _secilenFormat = "MP3");
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (_secilenFormat == "MP4") ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Çözünürlük Kalitesi: ", style: TextStyle(fontSize: 15)),
                          const SizedBox(width: 10),
                          DropdownButton<String>(
                            value: _secilenKalite,
                            dropdownColor: const Color(0xFF1F1F1F),
                            iconEnabledColor: Colors.redAccent,
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                            underline: Container(height: 2, color: Colors.redAccent),
                            onChanged: (String? yeniDeger) {
                              if (yeniDeger != null) {
                                setState(() {
                                  _secilenKalite = yeniDeger;
                                });
                              }
                            },
                            items: _kaliteListesi.map<DropdownMenuItem<String>>((String deger) {
                              return DropdownMenuItem<String>(
                                value: deger,
                                child: Text(deger),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 10),

                    if (_indirmeBasladiMi) ...[
                      LinearProgressIndicator(
                        value: _indirmeYuzdesi,
                        backgroundColor: Colors.grey[800],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                      ),
                      const SizedBox(height: 10),
                    ],

                    Text(
                      _durumMesaji,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 30),

                    ElevatedButton.icon(
                      onPressed: _indirmeBasladiMi ? null : _medyayiIndir,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(_indirmeBasladiMi ? 'İndiriliyor...' : 'İndirmeyi Başlat'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // sağ altta ki copyright ve orş yazısı için align padding
            Padding(
              padding: const EdgeInsets.only(right: 20.0, bottom: 10.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: const Text(
                  '© ORŞevik',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}