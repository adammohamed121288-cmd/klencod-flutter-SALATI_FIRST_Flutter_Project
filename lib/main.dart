import 'dart:async';
import 'dart:io';
import 'package:adhan_dart/adhan_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const green = Color(0xFF0D2B22);
const green2 = Color(0xFF174638);
const gold = Color(0xFFD8B66A);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SalatiApp());
}

class SalatiApp extends StatelessWidget {
  const SalatiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'صلاتي أولاً',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: green,
        colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.dark),
        fontFamily: 'sans-serif',
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class PrayerItem {
  final String name;
  final DateTime time;
  const PrayerItem(this.name, this.time);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const platform = MethodChannel('salati_first/native');
  final names = const ['الفجر', 'الظهر', 'العصر', 'المغرب', 'العشاء'];
  final keys = const ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
  final Map<String, String?> photos = {};
  final Set<String> completed = {};
  List<PrayerItem> prayers = [];
  bool loading = true;
  bool strictEnabled = false;
  bool accessibilityEnabled = false;
  String locationLabel = 'جارٍ تحديد موقعك';
  double lat = 31.2653; // Port Said fallback; replace after location permission.
  double lon = 32.3019;
  Timer? ticker;
  DateTime now = DateTime.now();
  String? activePrayer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => now = DateTime.now());
        _checkPrayerWindow();
      }
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermission();
      _checkPrayerWindow();
    }
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    strictEnabled = p.getBool('strict') ?? false;
    lat = p.getDouble('lat') ?? lat;
    lon = p.getDouble('lon') ?? lon;
    final saved = p.getStringList('completed_${_dateKey()}') ?? [];
    completed.addAll(saved);
    for (final k in keys) {
      final v = p.getString('photo_${_dateKey()}_$k');
      if (v != null) photos[k] = v;
    }
    await _refreshPermission();
    await _calculate();
    if (mounted) setState(() => loading = false);
  }

  String _dateKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _refreshPermission() async {
    try {
      accessibilityEnabled = await platform.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } catch (_) {
      accessibilityEnabled = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _calculate() async {
    try {
      final coordinates = Coordinates(lat, lon);
      final params = CalculationMethodParameters.egyptian();
      final pt = PrayerTimes(
        coordinates: coordinates,
        date: DateTime.now(),
        calculationParameters: params,
      );
      prayers = [
        PrayerItem('الفجر', pt.fajr.toLocal()),
        PrayerItem('الظهر', pt.dhuhr.toLocal()),
        PrayerItem('العصر', pt.asr.toLocal()),
        PrayerItem('المغرب', pt.maghrib.toLocal()),
        PrayerItem('العشاء', pt.isha.toLocal()),
      ];
      try {
        await platform.invokeMethod('setPrayerTimes', {
          'items': prayers.map((p) => {
            'key': _keyFor(p.name),
            'epoch': p.time.millisecondsSinceEpoch,
          }).toList(),
        });
      } catch (_) {}
      locationLabel = '${lat.toStringAsFixed(3)}, ${lon.toStringAsFixed(3)}';
      if (mounted) setState(() {});
    } catch (e) {
      locationLabel = 'تعذر حساب المواقيت';
    }
  }

  Future<void> _useLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _message('اسمح للتطبيق باستخدام الموقع أو استخدم الإعدادات اليدوية لاحقاً');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      lat = pos.latitude;
      lon = pos.longitude;
      final p = await SharedPreferences.getInstance();
      await p.setDouble('lat', lat);
      await p.setDouble('lon', lon);
      await _calculate();
      _message('تم تحديث مواقيت الصلاة حسب موقعك');
    } catch (_) {
      _message('لم نتمكن من تحديد الموقع');
    }
  }

  Future<void> _toggleStrict(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('strict', value);
    if (value && !accessibilityEnabled) {
      try {
        await platform.invokeMethod('openAccessibilitySettings');
      } catch (_) {}
      _message('فعّل خدمة صلاتي أولاً من إعدادات إمكانية الوصول ثم ارجع للتطبيق');
    }
    strictEnabled = value;
    try {
      await platform.invokeMethod('setStrictMode', {'enabled': value});
    } catch (_) {}
    await _refreshPermission();
    if (mounted) setState(() {});
  }

  void _checkPrayerWindow() {
    if (!strictEnabled || prayers.isEmpty) return;
    for (final prayer in prayers) {
      final diff = now.difference(prayer.time).inMinutes;
      if (diff >= 0 && diff < 20 && !completed.contains(_keyFor(prayer.name))) {
        if (activePrayer != prayer.name) {
          activePrayer = prayer.name;
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PrayerFocusPage(prayerName: prayer.name)),
            ).then((_) {
              activePrayer = null;
              _loadCompleted();
            });
          }
        }
        return;
      }
    }
  }

  String _keyFor(String name) => names.indexOf(name) >= 0 ? keys[names.indexOf(name)] : '';

  Future<void> _loadCompleted() async {
    final p = await SharedPreferences.getInstance();
    completed
      ..clear()
      ..addAll(p.getStringList('completed_${_dateKey()}') ?? []);
    if (mounted) setState(() {});
  }

  DateTime? get nextPrayer {
    for (final prayer in prayers) {
      if (prayer.time.isAfter(now)) return prayer.time;
    }
    return prayers.isEmpty ? null : prayers.first.time.add(const Duration(days: 1));
  }

  String get nextName {
    for (final prayer in prayers) {
      if (prayer.time.isAfter(now)) return prayer.name;
    }
    return prayers.isEmpty ? '—' : prayers.first.name;
  }

  String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'م' : 'ص'}';
  }

  String _countdown() {
    final n = nextPrayer;
    if (n == null) return '—';
    var seconds = n.difference(now).inSeconds;
    if (seconds < 0) seconds = 0;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _message(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), backgroundColor: green2));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: gold)));
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: green,
          title: const Text('صلاتي أولاً', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(onPressed: _useLocation, icon: const Icon(Icons.my_location, color: gold),
                tooltip: 'تحديث الموقع'),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async { await _calculate(); await _loadCompleted(); },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(colors: [green2, Color(0xFF092019)]),
                  border: Border.all(color: gold.withOpacity(.45)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.mosque, color: gold, size: 42),
                    const SizedBox(height: 10),
                    const Text('صلاتك أولاً', style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold, color: gold)),
                    const SizedBox(height: 8),
                    Text('الصلاة القادمة: $nextName', style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 5),
                    Text(_countdown(), style: const TextStyle(fontSize: 30, color: gold, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('الموقع: $locationLabel', style: TextStyle(color: Colors.white.withOpacity(.65), fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text('مواقيت الصلاة اليوم', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...prayers.map((p) {
                final key = _keyFor(p.name);
                final done = completed.contains(key);
                return Card(
                  color: const Color(0xFF15392E),
                  child: ListTile(
                    leading: Icon(done ? Icons.check_circle : Icons.access_time, color: done ? Colors.greenAccent : gold),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(done ? 'تم تسجيل الصلاة' : 'بانتظار تسجيل الصلاة'),
                    trailing: Text(_time(p.time), style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
                    onTap: () => _completePrayer(p.name),
                  ),
                );
              }),
              const SizedBox(height: 14),
              SwitchListTile(
                value: strictEnabled,
                onChanged: _toggleStrict,
                activeColor: gold,
                tileColor: const Color(0xFF15392E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('تفعيل الوضع الصارم', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(accessibilityEnabled ? 'خدمة تقييد التطبيقات مفعّلة' : 'يتطلب تفعيل خدمة إمكانية الوصول'),
                secondary: const Icon(Icons.shield_moon, color: gold),
              ),
              const SizedBox(height: 12),
              Card(
                color: const Color(0xFF15392E),
                child: ListTile(
                  leading: const Icon(Icons.photo_camera, color: gold),
                  title: const Text('سجل الصلاة والصور'),
                  subtitle: const Text('تسجيل الصلاة وتصوير السجادة اختيارياً'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _showHistory(),
                ),
              ),
              const SizedBox(height: 14),
              Text('خدمة التقييد: ${accessibilityEnabled ? "مفعّلة" : "غير مفعّلة"}',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(.55))),
              const SizedBox(height: 8),
              const Text('التطبيق وسيلة تذكير ومساعدة، والصورة أو التسجيل لا يثبتان أداء العبادة.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _completePrayer(String prayerName) async {
    final key = _keyFor(prayerName);
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList('completed_${_dateKey()}') ?? [];
    if (!list.contains(key)) list.add(key);
    await p.setStringList('completed_${_dateKey()}', list);
    try {
      await platform.invokeMethod('setPrayerCompleted', {'key': key, 'date': _dateKey()});
    } catch (_) {}
    completed.add(key);
    if (mounted) setState(() {});
    _message('تم تسجيل $prayerName. تقبّل الله منك ❤️');
  }

  Future<void> _showHistory() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: green2,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('سجل الصلاة اليوم', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: gold)),
              const SizedBox(height: 12),
              ...List.generate(5, (i) {
                final key = keys[i];
                return ListTile(
                  title: Text(names[i]),
                  leading: Icon(completed.contains(key) ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: completed.contains(key) ? Colors.greenAccent : gold),
                  trailing: IconButton(
                    icon: const Icon(Icons.camera_alt, color: gold),
                    onPressed: () async {
                      final image = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 75);
                      if (image != null) {
                        final p = await SharedPreferences.getInstance();
                        await p.setString('photo_${_dateKey()}_$key', image.path);
                        photos[key] = image.path;
                        if (mounted) setState(() {});
                        if (ctx.mounted) Navigator.pop(ctx);
                        _message('تم حفظ صورة السجادة على جهازك');
                      }
                    },
                  ),
                  subtitle: photos[key] != null && File(photos[key]!).existsSync()
                      ? const Text('تم حفظ صورة اختيارية')
                      : const Text('يمكنك تسجيل الصلاة أو تصوير السجادة اختيارياً'),
                  onTap: () => _completePrayer(names[i]),
                );
              }),
              const SizedBox(height: 8),
              const Text('لا يلزم تصوير السجادة ولا يُطلب منك الحلف. الصدق والنية بينك وبين الله.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
            ]),
          ),
        ),
      ),
    );
  }
}

class PrayerFocusPage extends StatelessWidget {
  final String prayerName;
  const PrayerFocusPage({super.key, required this.prayerName});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF071B14),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mosque, size: 88, color: gold),
                  const SizedBox(height: 28),
                  const Text('صــلاتــك أولاً', style: TextStyle(fontSize: 34, color: gold, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  Text('حان وقت صلاة $prayerName', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 18),
                  const Text('اترك ما يشغلك، وخذ وقتك مع الصلاة ❤️',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: Colors.white70)),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: green, padding: const EdgeInsets.all(16)),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('حسناً، سأذهب للصلاة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق التذكير')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}