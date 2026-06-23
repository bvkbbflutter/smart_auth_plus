import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_auth_plus/smart_auth_plus.dart';

void main() {
  runApp(const SmartAuthPlusExampleApp());
}

class SmartAuthPlusExampleApp extends StatelessWidget {
  const SmartAuthPlusExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartAuth Plus Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _auth = SmartAuthPlus();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // Stream subscriptions
  StreamSubscription<SmsResult>? _smsSub;
  StreamSubscription<PhoneHintResult>? _phoneSub;

  // State variables
  String? _appSignature;
  String? _statusMessage;
  bool _isLoading = false;
  String? _extractedCode;
  String? _selectedPhone;
  bool _smsListening = false;
  bool _retrieverListening = false;

  @override
  void initState() {
    super.initState();
    _getAppSignature();
  }

  @override
  void dispose() {
    _smsSub?.cancel();
    _phoneSub?.cancel();
    _auth.dispose();
    _otpController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ─── Helper Methods ─────────────────────────────────────────────────────

  void _setStatus(String message,
      {bool isError = false, bool isSuccess = false}) {
    setState(() {
      _statusMessage = message;
    });
  }

  void _setLoading(bool loading) {
    setState(() {
      _isLoading = loading;
    });
  }

  // ─── Get App Signature ──────────────────────────────────────────────────

  Future<void> _getAppSignature() async {
    _setLoading(true);
    try {
      final hash = await _auth.getAppSignature();
      setState(() {
        _appSignature = hash;
        _statusMessage = '✅ App signature retrieved successfully';
      });
      debugPrint('App Signature: $hash');
    } on AuthException catch (e) {
      setState(() {
        _statusMessage = '❌ Error [${e.code}]: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
    } finally {
      _setLoading(false);
    }
  }

  void _copySignature() {
    if (_appSignature == null) return;
    Clipboard.setData(ClipboardData(text: _appSignature!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hash copied to clipboard')),
    );
  }

  // ─── SMS User Consent ──────────────────────────────────────────────────

  Future<void> _startUserConsent() async {
    if (_smsListening) {
      _setStatus('⚠️ Already listening for SMS', isError: false);
      return;
    }

    _setLoading(true);
    _setStatus('⏳ Listening for SMS with User Consent...');
    setState(() {
      _extractedCode = null;
    });

    try {
      // Subscribe to the stream
      _smsSub = _auth.smsUserConsentStream().listen((result) {
        switch (result) {
          case SmsReceived(:final message):
            final code = _extractCodeFromMessage(message);
            setState(() {
              _extractedCode = code;
              if (code != null) {
                _otpController.text = code;
                _statusMessage = '✅ OTP extracted: $code';
              } else {
                _statusMessage = '⚠️ SMS received but no OTP found';
              }
              _smsListening = false;
            });
            debugPrint('SMS Received: $message');
            break;

          case SmsCanceled(:final reason):
            setState(() {
              _statusMessage = '⏹️ User canceled consent: $reason';
              _smsListening = false;
            });
            break;

          case SmsError(:final code, :final message):
            setState(() {
              _statusMessage = '❌ Error [$code]: $message';
              _smsListening = false;
            });
            break;
        }
        _setLoading(false);
      });

      // Start the native listener
      await _auth.startSmsUserConsent();
      setState(() {
        _smsListening = true;
        _statusMessage = '👂 Waiting for SMS (User Consent)...';
      });
    } on AuthException catch (e) {
      setState(() {
        _statusMessage = '❌ AuthException [${e.code}]: ${e.message}';
        _smsListening = false;
      });
      _setLoading(false);
    }
  }

  // ─── SMS Retriever (Automatic) ─────────────────────────────────────────

  Future<void> _startSmsRetriever() async {
    if (_retrieverListening) {
      _setStatus('⚠️ Already listening with Retriever', isError: false);
      return;
    }

    _setLoading(true);
    _setStatus('⏳ Listening for SMS with Retriever...');
    setState(() {
      _extractedCode = null;
    });

    try {
      // Subscribe to the stream
      _smsSub = _auth.smsRetrieverStream().listen((result) {
        switch (result) {
          case SmsReceived(:final message):
            final code = _extractCodeFromMessage(message);
            setState(() {
              _extractedCode = code;
              if (code != null) {
                _otpController.text = code;
                _statusMessage = '✅ OTP auto-extracted: $code';
              } else {
                _statusMessage = '⚠️ SMS received but no OTP found';
              }
              _retrieverListening = false;
            });
            debugPrint('SMS Auto-Retrieved: $message');
            break;

          case SmsCanceled(:final reason):
            setState(() {
              _statusMessage = '⏹️ Retriever canceled: $reason';
              _retrieverListening = false;
            });
            break;

          case SmsError(:final code, :final message):
            setState(() {
              _statusMessage = '❌ Error [$code]: $message';
              _retrieverListening = false;
            });
            break;
        }
        _setLoading(false);
      });

      // Start the native retriever
      await _auth.startSmsRetriever();
      setState(() {
        _retrieverListening = true;
        _statusMessage = '👂 Waiting for SMS (Retriever - no dialog)...';
      });
    } on AuthException catch (e) {
      setState(() {
        _statusMessage = '❌ AuthException [${e.code}]: ${e.message}';
        _retrieverListening = false;
      });
      _setLoading(false);
    }
  }

  // ─── Cancel SMS Listener ───────────────────────────────────────────────

  Future<void> _cancelSmsListener() async {
    await _auth.cancelSmsListener();
    await _smsSub?.cancel();
    _smsSub = null;
    setState(() {
      _smsListening = false;
      _retrieverListening = false;
      _statusMessage = '🛑 SMS listener canceled';
    });
  }

  // ─── Phone Number Hint ──────────────────────────────────────────────────

  Future<void> _requestPhoneNumberHint() async {
    _setLoading(true);
    _setStatus('⏳ Requesting phone number...');

    try {
      _phoneSub = _auth.phoneHintStream().listen((result) {
        switch (result) {
          case PhoneHintSelected(:final phoneNumber):
            setState(() {
              _selectedPhone = phoneNumber;
              _phoneController.text = phoneNumber;
              _statusMessage = '✅ Phone selected: $phoneNumber';
            });
            debugPrint('Phone Selected: $phoneNumber');
            break;

          case PhoneHintCanceled(:final reason):
            setState(() {
              _statusMessage = '⏹️ Phone hint dismissed: $reason';
            });
            break;

          case PhoneHintError(:final code, :final message):
            setState(() {
              _statusMessage = '❌ Error [$code]: $message';
            });
            break;
        }
        _setLoading(false);
      });

      await _auth.requestPhoneNumberHint(
        title: 'Choose your number',
        subtitle: 'Select for OTP verification',
      );
      _setStatus('📋 Phone number picker shown');
    } on AuthException catch (e) {
      setState(() {
        _statusMessage = '❌ AuthException [${e.code}]: ${e.message}';
      });
      _setLoading(false);
    }
  }

  // ─── OTP Verification ──────────────────────────────────────────────────

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.isEmpty) {
      _setStatus('⚠️ Please enter or extract an OTP first', isError: false);
      return;
    }

    _setLoading(true);
    _setStatus('🔍 Verifying OTP: $code...');

    // Simulate API verification
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      if (code.length >= 4 && code.length <= 6) {
        _statusMessage = '✅ OTP Verified Successfully! 🎉';
      } else {
        _statusMessage = '❌ Invalid OTP. Please try again.';
      }
      _isLoading = false;
    });
  }

  // ─── Extract OTP from SMS ─────────────────────────────────────────────

  String? _extractCodeFromMessage(String message) {
    // Common OTP patterns
    final patterns = [
      r'\b\d{4,6}\b', // 4-6 digit code
      r'OTP[:\s]*(\d{4,6})', // OTP: 123456
      r'code[:\s]*(\d{4,6})', // code: 123456
      r'verification[:\s]*(\d{4,6})', // verification: 123456
    ];

    for (final pattern in patterns) {
      final regex = RegExp(pattern, caseSensitive: false);
      final match = regex.firstMatch(message);
      if (match != null) {
        final code = match.groupCount > 0 ? match.group(1) : match.group(0);
        if (code != null) return code;
      }
    }
    return null;
  }

  // ─── Clear Fields ──────────────────────────────────────────────────────

  void _clearFields() {
    setState(() {
      _otpController.clear();
      _phoneController.clear();
      _extractedCode = null;
      _selectedPhone = null;
      _statusMessage = '🧹 Fields cleared';
    });
  }

  // ─── Build UI ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isListening = _smsListening || _retrieverListening;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartAuth Plus Demo'),
        centerTitle: true,
        elevation: 2,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _getAppSignature,
            tooltip: 'Refresh App Signature',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── App Signature Section ─────────────────────────────────
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'App Signature Hash',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_appSignature != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  _appSignature!,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _copySignature,
                                icon: const Icon(Icons.copy, size: 20),
                                tooltip: 'Copy hash',
                              ),
                            ],
                          ),
                        )
                      else
                        const Text('Loading app signature...'),
                      const SizedBox(height: 8),
                      Text(
                        'Add this hash at the end of your SMS:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (_appSignature != null)
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: SelectableText(
                            'Your OTP is 123456\n\n$_appSignature',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ─── Phone Number Section ─────────────────────────────────
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Phone Number',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _phoneController,
                        decoration: InputDecoration(
                          hintText: 'Enter or select phone number',
                          prefixIcon: const Icon(Icons.phone),
                          suffixIcon: _selectedPhone != null
                              ? IconButton(
                                  icon: const Icon(Icons.check_circle,
                                      color: Colors.green),
                                  onPressed: null,
                                )
                              : null,
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        keyboardType: TextInputType.phone,
                        readOnly: true,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _requestPhoneNumberHint,
                        icon: const Icon(Icons.person_search),
                        label: const Text('Get Phone Number Hint'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ─── OTP Section ───────────────────────────────────────────
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'OTP Verification',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _otpController,
                        decoration: InputDecoration(
                          hintText: 'Enter OTP code',
                          prefixIcon: const Icon(Icons.security),
                          suffixIcon: _extractedCode != null
                              ? IconButton(
                                  icon: const Icon(Icons.check_circle,
                                      color: Colors.green),
                                  onPressed: null,
                                )
                              : null,
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          counterText: '',
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLoading || _smsListening
                                  ? null
                                  : _startUserConsent,
                              icon: _smsListening
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.sms),
                              label: Text(_smsListening
                                  ? 'Listening...'
                                  : 'Auto-read SMS'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLoading || _retrieverListening
                                  ? null
                                  : _startSmsRetriever,
                              icon: _retrieverListening
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.sync),
                              label: Text(_retrieverListening
                                  ? 'Listening...'
                                  : 'SMS Retriever'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isListening) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _cancelSmsListener,
                          icon: const Icon(Icons.stop),
                          label: const Text('Cancel SMS Listener'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _verifyOtp,
                              icon: const Icon(Icons.verified),
                              label: const Text('Verify OTP'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _clearFields,
                            icon: const Icon(Icons.clear_all),
                            label: const Text('Clear'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ─── Status Message ──────────────────────────────────────
              if (_statusMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusMessage!.startsWith('✅')
                        ? Colors.green.shade100
                        : _statusMessage!.startsWith('❌')
                            ? Colors.red.shade100
                            : _statusMessage!.startsWith('⚠️')
                                ? Colors.orange.shade100
                                : _statusMessage!.startsWith('⏹️')
                                    ? Colors.grey.shade100
                                    : Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _statusMessage!.startsWith('✅')
                          ? Colors.green
                          : _statusMessage!.startsWith('❌')
                              ? Colors.red
                              : _statusMessage!.startsWith('⚠️')
                                  ? Colors.orange
                                  : _statusMessage!.startsWith('⏹️')
                                      ? Colors.grey
                                      : Colors.blue,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _statusMessage!.startsWith('✅')
                            ? Icons.check_circle
                            : _statusMessage!.startsWith('❌')
                                ? Icons.error
                                : _statusMessage!.startsWith('⚠️')
                                    ? Icons.warning
                                    : _statusMessage!.startsWith('⏹️')
                                        ? Icons.cancel
                                        : Icons.info,
                        color: _statusMessage!.startsWith('✅')
                            ? Colors.green
                            : _statusMessage!.startsWith('❌')
                                ? Colors.red
                                : _statusMessage!.startsWith('⚠️')
                                    ? Colors.orange
                                    : _statusMessage!.startsWith('⏹️')
                                        ? Colors.grey
                                        : Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _statusMessage = null),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // ─── Info Footer ──────────────────────────────────────────
              Card(
                elevation: 2,
                color: Colors.grey.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📱 How it works:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '1. Send test SMS to this device\n'
                        '2. Tap "Auto-read SMS" to extract OTP\n'
                        '3. OTP will be automatically filled\n'
                        '4. Tap "Verify OTP" to simulate verification\n\n'
                        '💡 Test SMS format: "Your OTP is 123456"\n'
                        '🔑 App Signature is required for SMS Retriever',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

              // ─── Loading Overlay ──────────────────────────────────────
              if (_isLoading)
                Container(
                  height: 4,
                  child: const LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:smart_auth_plus/smart_auth_plus.dart';

// void main() {
//   runApp(const SmartAuthPlusExampleApp());
// }

// class SmartAuthPlusExampleApp extends StatelessWidget {
//   const SmartAuthPlusExampleApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'SmartAuthPlus Demo',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         colorSchemeSeed: const Color(0xFF6750A4),
//         useMaterial3: true,
//       ),
//       home: const HomePage(),
//     );
//   }
// }

// // ─── Home Page ─────────────────────────────────────────────────────────────

// class HomePage extends StatefulWidget {
//   const HomePage({super.key});

//   @override
//   State<HomePage> createState() => _HomePageState();
// }

// class _HomePageState extends State<HomePage> {
//   final _auth = SmartAuthPlus();
//   final List<_LogEntry> _logs = [];

//   StreamSubscription<SmsResult>? _smsSub;
//   StreamSubscription<PhoneHintResult>? _phoneSub;

//   bool _smsListening = false;
//   bool _retrieverListening = false;
//   String? _appSignature;

//   // ─── Lifecycle ──────────────────────────────────────────────────────────

//   @override
//   void dispose() {
//     _smsSub?.cancel();
//     _phoneSub?.cancel();
//     _auth.dispose();
//     super.dispose();
//   }

//   // ─── Logging helpers ────────────────────────────────────────────────────

//   void _log(String message, {LogLevel level = LogLevel.info}) {
//     setState(() {
//       _logs.insert(
//           0, _LogEntry(message: message, level: level, time: DateTime.now()));
//     });
//   }

//   void _clearLogs() => setState(() => _logs.clear());

//   // ─── Feature 1: SMS User Consent ────────────────────────────────────────

//   Future<void> _startUserConsent() async {
//     if (_smsListening) {
//       _log('Already listening for SMS (User Consent)', level: LogLevel.warning);
//       return;
//     }
//     try {
//       // 1. Subscribe to the stream first.
//       _smsSub = _auth.smsUserConsentStream().listen((result) {
//         switch (result) {
//           case SmsReceived(:final message):
//             _log('✅ SMS received:\n$message', level: LogLevel.success);
//           case SmsCanceled(:final reason):
//             _log('⚠️ SMS consent canceled. Reason: $reason',
//                 level: LogLevel.warning);
//           case SmsError(:final code, :final message):
//             _log('❌ Error [$code]: $message', level: LogLevel.error);
//         }
//         setState(() => _smsListening = false);
//       });

//       // 2. Then start the native listener.
//       await _auth.startSmsUserConsent();
//       setState(() => _smsListening = true);
//       _log('👂 Waiting for SMS (User Consent)…');
//     } on AuthException catch (e) {
//       _log('❌ AuthException [${e.code}]: ${e.message}', level: LogLevel.error);
//     }
//   }

//   // ─── Feature 2: SMS Retriever ────────────────────────────────────────────

//   Future<void> _startRetriever() async {
//     if (_retrieverListening) {
//       _log('Already listening (SMS Retriever)', level: LogLevel.warning);
//       return;
//     }
//     try {
//       // 1. Subscribe first.
//       _smsSub = _auth.smsRetrieverStream().listen((result) {
//         switch (result) {
//           case SmsReceived(:final message):
//             _log('✅ SMS auto-retrieved:\n$message', level: LogLevel.success);
//           case SmsCanceled(:final reason):
//             _log('⚠️ Retriever canceled. Reason: $reason',
//                 level: LogLevel.warning);
//           case SmsError(:final code, :final message):
//             _log('❌ Error [$code]: $message', level: LogLevel.error);
//         }
//         setState(() => _retrieverListening = false);
//       });

//       // 2. Start native retriever.
//       await _auth.startSmsRetriever();
//       setState(() => _retrieverListening = true);
//       _log('👂 Waiting for SMS (Retriever – no dialog)…');
//     } on AuthException catch (e) {
//       _log('❌ AuthException [${e.code}]: ${e.message}', level: LogLevel.error);
//     }
//   }

//   Future<void> _cancelSmsListener() async {
//     await _auth.cancelSmsListener();
//     await _smsSub?.cancel();
//     _smsSub = null;
//     setState(() {
//       _smsListening = false;
//       _retrieverListening = false;
//     });
//     _log('🛑 SMS listener canceled');
//   }

//   // ─── Feature 3: Phone Number Hint ───────────────────────────────────────

//   Future<void> _requestPhoneHint() async {
//     try {
//       _phoneSub = _auth.phoneHintStream().listen((result) {
//         switch (result) {
//           case PhoneHintSelected(:final phoneNumber):
//             _log('📱 Phone selected: $phoneNumber', level: LogLevel.success);
//           case PhoneHintCanceled(:final reason):
//             _log('⚠️ Phone hint dismissed. Reason: $reason',
//                 level: LogLevel.warning);
//           case PhoneHintError(:final code, :final message):
//             _log('❌ Error [$code]: $message', level: LogLevel.error);
//         }
//       });

//       await _auth.requestPhoneNumberHint(
//         title: 'Choose your number',
//         subtitle: 'Select for OTP verification',
//       );
//       _log('📋 Phone number picker shown');
//     } on AuthException catch (e) {
//       _log('❌ AuthException [${e.code}]: ${e.message}', level: LogLevel.error);
//     }
//   }

//   // ─── Feature 4: App Signature ────────────────────────────────────────────

//   Future<void> _getAppSignature() async {
//     try {
//       final hash = await _auth.getAppSignature();
//       setState(() => _appSignature = hash);
//       _log('🔑 App Signature Hash: $hash', level: LogLevel.success);
//     } on AuthException catch (e) {
//       _log('❌ AuthException [${e.code}]: ${e.message}', level: LogLevel.error);
//     }
//   }

//   void _copySignature() {
//     if (_appSignature == null) return;
//     Clipboard.setData(ClipboardData(text: _appSignature!));
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Hash copied to clipboard')),
//     );
//   }

//   // ─── Build ───────────────────────────────────────────────────────────────

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('SmartAuthPlus Demo'),
//         centerTitle: true,
//         backgroundColor: theme.colorScheme.primaryContainer,
//       ),
//       body: Column(
//         children: [
//           Expanded(
//             child: SingleChildScrollView(
//               padding: const EdgeInsets.all(16),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.stretch,
//                 children: [
//                   _FeatureCard(
//                     icon: Icons.sms_outlined,
//                     title: 'SMS User Consent',
//                     subtitle:
//                         'Shows a system dialog asking the user to approve sharing a specific SMS.',
//                     color: Colors.purple,
//                     children: [
//                       Row(children: [
//                         Expanded(
//                           child: FilledButton.icon(
//                             onPressed: _smsListening ? null : _startUserConsent,
//                             icon: _smsListening
//                                 ? const SizedBox(
//                                     width: 16,
//                                     height: 16,
//                                     child: CircularProgressIndicator(
//                                         strokeWidth: 2))
//                                 : const Icon(Icons.play_arrow),
//                             label: Text(_smsListening ? 'Listening…' : 'Start'),
//                           ),
//                         ),
//                         const SizedBox(width: 8),
//                         OutlinedButton.icon(
//                           onPressed: (_smsListening || _retrieverListening)
//                               ? _cancelSmsListener
//                               : null,
//                           icon: const Icon(Icons.stop),
//                           label: const Text('Cancel'),
//                         ),
//                       ]),
//                     ],
//                   ),
//                   const SizedBox(height: 12),
//                   _FeatureCard(
//                     icon: Icons.auto_awesome_outlined,
//                     title: 'SMS Retriever (Automatic)',
//                     subtitle:
//                         'No dialog. SMS must end with your 11-char app hash. Fully automatic.',
//                     color: Colors.indigo,
//                     children: [
//                       Row(children: [
//                         Expanded(
//                           child: FilledButton.icon(
//                             onPressed:
//                                 _retrieverListening ? null : _startRetriever,
//                             icon: _retrieverListening
//                                 ? const SizedBox(
//                                     width: 16,
//                                     height: 16,
//                                     child: CircularProgressIndicator(
//                                         strokeWidth: 2))
//                                 : const Icon(Icons.play_arrow),
//                             label: Text(
//                                 _retrieverListening ? 'Listening…' : 'Start'),
//                           ),
//                         ),
//                         const SizedBox(width: 8),
//                         OutlinedButton.icon(
//                           onPressed: (_smsListening || _retrieverListening)
//                               ? _cancelSmsListener
//                               : null,
//                           icon: const Icon(Icons.stop),
//                           label: const Text('Cancel'),
//                         ),
//                       ]),
//                     ],
//                   ),
//                   const SizedBox(height: 12),
//                   _FeatureCard(
//                     icon: Icons.phone_outlined,
//                     title: 'Phone Number Hint',
//                     subtitle:
//                         'Shows system picker with phone numbers from the device account.',
//                     color: Colors.teal,
//                     children: [
//                       FilledButton.icon(
//                         onPressed: _requestPhoneHint,
//                         icon: const Icon(Icons.dialpad),
//                         label: const Text('Show Phone Picker'),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 12),
//                   _FeatureCard(
//                     icon: Icons.fingerprint,
//                     title: 'App Signature Hash',
//                     subtitle:
//                         'Generate the 11-char hash for your SMS template. Use in dev only.',
//                     color: Colors.orange,
//                     children: [
//                       FilledButton.icon(
//                         onPressed: _getAppSignature,
//                         icon: const Icon(Icons.generating_tokens),
//                         label: const Text('Get Hash'),
//                       ),
//                       if (_appSignature != null) ...[
//                         const SizedBox(height: 8),
//                         Container(
//                           padding: const EdgeInsets.symmetric(
//                               horizontal: 12, vertical: 8),
//                           decoration: BoxDecoration(
//                             color: Colors.orange.shade50,
//                             borderRadius: BorderRadius.circular(8),
//                             border: Border.all(color: Colors.orange.shade200),
//                           ),
//                           child: Row(
//                             children: [
//                               Expanded(
//                                 child: Text(
//                                   _appSignature!,
//                                   style: const TextStyle(
//                                       fontFamily: 'monospace',
//                                       fontWeight: FontWeight.bold,
//                                       fontSize: 16),
//                                 ),
//                               ),
//                               IconButton(
//                                 onPressed: _copySignature,
//                                 icon: const Icon(Icons.copy),
//                                 tooltip: 'Copy hash',
//                               ),
//                             ],
//                           ),
//                         ),
//                         Text(
//                           'Add to end of your SMS:\n"Your OTP is 123456\n\n$_appSignature"',
//                           style: theme.textTheme.bodySmall
//                               ?.copyWith(color: Colors.grey),
//                         ),
//                       ],
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//           ),

//           // ── Event Log ──────────────────────────────────────────────────
//           _EventLog(logs: _logs, onClear: _clearLogs),
//         ],
//       ),
//     );
//   }
// }

// // ─── Widgets ─────────────────────────────────────────────────────────────────

// class _FeatureCard extends StatelessWidget {
//   const _FeatureCard({
//     required this.icon,
//     required this.title,
//     required this.subtitle,
//     required this.color,
//     required this.children,
//   });

//   final IconData icon;
//   final String title;
//   final String subtitle;
//   final Color color;
//   final List<Widget> children;

//   @override
//   Widget build(BuildContext context) {
//     return Card(
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(children: [
//               CircleAvatar(
//                 backgroundColor: color.withOpacity(0.15),
//                 child: Icon(icon, color: color),
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(title,
//                         style: const TextStyle(
//                             fontWeight: FontWeight.bold, fontSize: 15)),
//                     Text(subtitle,
//                         style: TextStyle(
//                             color: Colors.grey.shade600, fontSize: 12)),
//                   ],
//                 ),
//               ),
//             ]),
//             const SizedBox(height: 12),
//             ...children,
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _EventLog extends StatelessWidget {
//   const _EventLog({required this.logs, required this.onClear});
//   final List<_LogEntry> logs;
//   final VoidCallback onClear;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: 220,
//       decoration: BoxDecoration(
//         color: const Color(0xFF1E1E1E),
//         border: Border(top: BorderSide(color: Colors.grey.shade800)),
//       ),
//       child: Column(
//         children: [
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//             child: Row(
//               children: [
//                 const Icon(Icons.terminal, color: Colors.green, size: 16),
//                 const SizedBox(width: 8),
//                 const Text('Event Log',
//                     style: TextStyle(color: Colors.green, fontSize: 12)),
//                 const Spacer(),
//                 TextButton(
//                   onPressed: onClear,
//                   child: const Text('Clear',
//                       style: TextStyle(color: Colors.grey, fontSize: 12)),
//                 ),
//               ],
//             ),
//           ),
//           const Divider(color: Colors.grey, height: 1),
//           Expanded(
//             child: logs.isEmpty
//                 ? const Center(
//                     child: Text('No events yet',
//                         style: TextStyle(color: Colors.grey, fontSize: 12)))
//                 : ListView.builder(
//                     padding: const EdgeInsets.all(8),
//                     itemCount: logs.length,
//                     itemBuilder: (_, i) {
//                       final entry = logs[i];
//                       return Padding(
//                         padding: const EdgeInsets.symmetric(vertical: 2),
//                         child: RichText(
//                           text: TextSpan(children: [
//                             TextSpan(
//                               text:
//                                   '[${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}] ',
//                               style: const TextStyle(
//                                   color: Colors.grey, fontSize: 11),
//                             ),
//                             TextSpan(
//                               text: entry.message,
//                               style: TextStyle(
//                                 color: entry.level.color,
//                                 fontSize: 12,
//                                 fontFamily: 'monospace',
//                               ),
//                             ),
//                           ]),
//                         ),
//                       );
//                     },
//                   ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // ─── Data ─────────────────────────────────────────────────────────────────────

// enum LogLevel {
//   info,
//   success,
//   warning,
//   error;

//   Color get color => switch (this) {
//         LogLevel.info => Colors.white70,
//         LogLevel.success => Colors.greenAccent,
//         LogLevel.warning => Colors.orangeAccent,
//         LogLevel.error => Colors.redAccent,
//       };
// }

// class _LogEntry {
//   final String message;
//   final LogLevel level;
//   final DateTime time;
//   const _LogEntry(
//       {required this.message, required this.level, required this.time});
// }
