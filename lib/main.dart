import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

const String TARGET_DEVICE_NAME_PREFIX = "Configurador_";
const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String SCHEMA_CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
const String DATA_CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a9";

class ConfigField {
  final String key;
  final String label;
  final String type;
  final bool isRequired;
  final dynamic value;

  ConfigField({
    required this.key,
    required this.label,
    required this.type,
    this.isRequired = false,
    this.value,
  });

  factory ConfigField.fromJson(Map<String, dynamic> json) {
    return ConfigField(
      key: json['key'] ?? '',
      label: json['label'] ?? 'Campo sin etiqueta',
      type: json['type'] ?? 'string',
      isRequired: json['required'] ?? false,
      value: json['value'],
    );
  }
}

void main() {
  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Configurador de Bluetooth',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
        useMaterial3: true,
      ),
      home: StreamBuilder<BluetoothAdapterState>(
        stream: FlutterBluePlus.adapterState,
        initialData: BluetoothAdapterState.unknown,
        builder: (context, snapshot) {
          final state = snapshot.data;
          if (state == BluetoothAdapterState.on) {
            return const ScanPage();
          }
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bluetooth_disabled, size: 80, color: Colors.grey),
                  const SizedBox(height: 20),
                  Text('Bluetooth está apagado', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  const Text('Por favor, enciende el Bluetooth para continuar.'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;

  @override
  void initState() {
    super.initState();
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      final filteredResults = results.where((r) => r.device.platformName.startsWith(TARGET_DEVICE_NAME_PREFIX)).toList();
      filteredResults.sort((a, b) => b.rssi.compareTo(a.rssi));
      if (mounted) {
        setState(() {
          _scanResults = filteredResults;
        });
      }
    });

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      if (mounted) {
        setState(() {
          _isScanning = state;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScan();
    });
  }

  @override
  void dispose() {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    if (await Permission.bluetoothScan.request().isGranted && await Permission.bluetoothConnect.request().isGranted) {
      return true;
    }
    return false;
  }

  Future<void> _startScan() async {
    if (await _requestPermissions()) {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } else {
      _showSnackbar("Se requieren permisos para buscar dispositivos.", isError: true);
    }
  }

  void _connectToDevice(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => DeviceConfigPage(device: device)));
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar Dispositivos')),
      body: RefreshIndicator(
        onRefresh: _startScan,
        child: Column(
          children: [
            if (_isScanning) const LinearProgressIndicator(),
            Expanded(
              child: _scanResults.isEmpty
                  ? Center(child: Text(_isScanning ? "Escaneando..." : "No se encontraron dispositivos.\nArrastra para escanear.", textAlign: TextAlign.center))
                  : ListView.builder(
                      itemCount: _scanResults.length,
                      itemBuilder: (context, index) {
                        final result = _scanResults[index];
                        return ListTile(
                          leading: const Icon(Icons.memory),
                          title: Text(result.device.platformName.isEmpty ? "Dispositivo sin nombre" : result.device.platformName),
                          subtitle: Text(result.device.remoteId.toString()),
                          trailing: Text("${result.rssi} dBm"),
                          onTap: () => _connectToDevice(result.device),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? null : _startScan,
        backgroundColor: _isScanning ? Colors.grey : Theme.of(context).primaryColor,
        child: _isScanning ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3.0)) : const Icon(Icons.search_rounded),
      ),
    );
  }
}

class DeviceConfigPage extends StatefulWidget {
  final BluetoothDevice device;
  const DeviceConfigPage({super.key, required this.device});

  @override
  State<DeviceConfigPage> createState() => _DeviceConfigPageState();
}

class _DeviceConfigPageState extends State<DeviceConfigPage> {
  String _connectionStatus = "Conectando...";
  bool _isLoading = true;
  BluetoothCharacteristic? _schemaCharacteristic;
  BluetoothCharacteristic? _dataCharacteristic;
  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;

  List<ConfigField> _configFields = [];
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, bool> _boolValues = {};
  final Map<String, bool> _passwordVisible = {};

  @override
  void initState() {
    super.initState();
    _connectionStateSubscription = widget.device.connectionState.listen((state) {
      if (mounted) {
        setState(() => _connectionStatus = state.toString().split('.').last);
        if (state == BluetoothConnectionState.disconnected) {
          _showSnackbar("Dispositivo desconectado.", isError: true);
          Navigator.of(context).pop();
        }
      }
    });
    Future.delayed(Duration.zero, () => _handleConnection());
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    _textControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _handleConnection() async {
    try {
      await widget.device.connect(timeout: const Duration(seconds: 15));
      await _discoverServices();
    } catch (e) {
      if (mounted) {
        _showSnackbar("Error en la conexión: $e", isError: true);
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _discoverServices() async {
    setState(() => _isLoading = true);
    try {
      List<BluetoothService> services = await widget.device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == SERVICE_UUID) {
          for (var char in service.characteristics) {
            String charUuid = char.uuid.toString().toLowerCase();
            if (charUuid == SCHEMA_CHARACTERISTIC_UUID) _schemaCharacteristic = char;
            if (charUuid == DATA_CHARACTERISTIC_UUID) _dataCharacteristic = char;
          }
        }
      }
      if (_schemaCharacteristic != null && _dataCharacteristic != null) {
        await _fetchAndBuildForm();
      } else {
        _showSnackbar("Servicios requeridos no encontrados.", isError: true);
      }
    } catch (e) {
      _showSnackbar("Error al descubrir servicios: $e", isError: true);
    }
    setState(() => _isLoading = false);
  }

  Future<void> _fetchAndBuildForm() async {
    try {
      final value = await _schemaCharacteristic!.read();
      final jsonString = utf8.decode(value);
      final schemaList = jsonDecode(jsonString) as List<dynamic>;

      setState(() {
        _configFields = schemaList.map((json) => ConfigField.fromJson(json)).toList();
        _textControllers.clear();
        _boolValues.clear();
        _passwordVisible.clear();
        for (var field in _configFields) {
          if (['string', 'password', 'int'].contains(field.type)) {
            _textControllers[field.key] = TextEditingController(text: field.value?.toString() ?? '');
            if (field.type == 'password') {
              _passwordVisible[field.key] = false;
            }
          } else if (field.type == 'bool') {
            _boolValues[field.key] = field.value is bool ? field.value : false;
          }
        }
      });
    } catch (e) {
      _showSnackbar("Error al leer el esquema de configuración: $e", isError: true);
    }
  }

  Future<void> _sendData() async {
    if (_dataCharacteristic == null) return;

    final Map<String, dynamic> dataToSend = {};

    for (var field in _configFields) {
      if (['string', 'password', 'int'].contains(field.type)) {
        final controller = _textControllers[field.key];
        final textValue = controller?.text ?? '';
        if (field.isRequired && textValue.isEmpty) {
          _showSnackbar("El campo '${field.label}' es obligatorio.", isError: true);
          return;
        }
        if (textValue.isNotEmpty) {
          if (field.type == 'int') {
            dataToSend[field.key] = int.tryParse(textValue) ?? 0;
          } else {
            dataToSend[field.key] = textValue;
          }
        }
      } else if (field.type == 'bool') {
        dataToSend[field.key] = _boolValues[field.key] ?? false;
      }
    }

    String jsonString = jsonEncode(dataToSend);
    List<int> bytes = utf8.encode(jsonString);

    try {
      await _dataCharacteristic!.write(bytes);
      _showSnackbar("Datos enviados. El dispositivo se reiniciará.");
    } catch (e) {
      _showSnackbar("Error al enviar datos: $e", isError: true);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.platformName.isEmpty ? "Dispositivo" : widget.device.platformName)),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildStatusCard(context, "Estado", _connectionStatus, Icons.bluetooth_connected, _isLoading),
          const SizedBox(height: 24),
          _buildConfigForm(),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, String title, String value, IconData icon, bool isLoading) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 40, color: Theme.of(context).primaryColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3.0)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigForm() {
    if (_isLoading) return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
    if (_configFields.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(24.0), child: Text("No se pudo cargar el formulario.", textAlign: TextAlign.center)));

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Parámetros Configurables", style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            ..._configFields.map((field) => _buildFormField(field)).toList(),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Guardar en Dispositivo'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), textStyle: const TextStyle(fontSize: 16)),
              onPressed: _sendData,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormField(ConfigField field) {
    Widget formField;
    switch (field.type) {
      case 'bool':
        formField = SwitchListTile(
          title: Text(field.label),
          value: _boolValues[field.key] ?? false,
          onChanged: (value) {
            setState(() {
              _boolValues[field.key] = value;
            });
          },
          contentPadding: EdgeInsets.zero,
        );
        break;
      case 'int':
        formField = TextField(
          controller: _textControllers[field.key],
          decoration: InputDecoration(
            labelText: field.label + (field.isRequired ? ' *' : ''),
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        );
        break;
      case 'password':
        formField = TextField(
          controller: _textControllers[field.key],
          obscureText: !(_passwordVisible[field.key] ?? false),
          decoration: InputDecoration(
            labelText: field.label + (field.isRequired ? ' *' : ''),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                (_passwordVisible[field.key] ?? false) ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () {
                setState(() {
                  _passwordVisible[field.key] = !(_passwordVisible[field.key] ?? false);
                });
              },
            ),
          ),
        );
        break;
      case 'string':
      default:
        formField = TextField(
          controller: _textControllers[field.key],
          decoration: InputDecoration(
            labelText: field.label + (field.isRequired ? ' *' : ''),
            border: const OutlineInputBorder(),
          ),
        );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: formField,
    );
  }
}
