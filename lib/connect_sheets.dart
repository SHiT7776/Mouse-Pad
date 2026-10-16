import 'dart:async';

import 'package:flutter/material.dart';

import 'links/bluetooth_link.dart';
import 'pad_theme.dart';

Future<void> showUsbHelp(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _UsbHelp(),
    );

Future<void> showBluetoothPicker(BuildContext context, BluetoothLink link) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BluetoothPicker(link: link),
    );

class _UsbHelp extends StatelessWidget {
  const _UsbHelp();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connect with a USB cable',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('Set this up once. After that, just plug in.',
                style: TextStyle(color: PadColors.textDim)),
            SizedBox(height: 18),
            StepRow(1,
                'On this phone, open Settings › About phone and tap "Build '
                'number" (on Xiaomi: "OS version") 7 times.'),
            StepRow(2,
                'Open Developer options (Settings › System, or Additional '
                'settings) and turn on "USB debugging".'),
            StepRow(3, 'On the PC, open Mouse Pad Receiver.'),
            StepRow(4,
                'Plug the phone into the PC. If the phone asks "Allow USB '
                'debugging?", tick "Always allow" and tap Allow.'),
            SizedBox(height: 4),
            Text('Mouse Pad connects by itself when both are ready.',
                style: TextStyle(color: PadColors.textDim, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

class _BluetoothPicker extends StatefulWidget {
  const _BluetoothPicker({required this.link});

  final BluetoothLink link;

  @override
  State<_BluetoothPicker> createState() => _BluetoothPickerState();
}

class _BluetoothPickerState extends State<_BluetoothPicker> {
  Timer? _tick;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.link.refreshPaired());
    widget.link.addListener(_onLink);
    // Counts down "Visible for 1:59".
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.link.discoverableUntil != null) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.link.removeListener(_onLink);
    _tick?.cancel();
    super.dispose();
  }

  void _onLink() {
    if (!mounted) return;
    setState(() {});
    if (widget.link.connected && !_closing) {
      _closing = true;
      // Show "Connected" for a moment, then get out of the way.
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final left = link.discoverableUntil?.difference(DateTime.now());
    final visible = left != null && left > Duration.zero;
    final connecting = link.phase == BtPhase.connecting ||
        link.phase == BtPhase.reconnecting;
    const dim = TextStyle(color: PadColors.textDim, fontSize: 13);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      link.connected
                          ? 'Connected!'
                          : connecting
                              ? 'Connecting…'
                              : 'Choose your PC',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('PCs paired with this phone:', style: dim),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 190),
                    child: link.paired.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                                'None yet. Pair your PC first (see the right).',
                                style: dim),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final device in link.paired)
                                _DeviceTile(
                                  device: device,
                                  busy: connecting &&
                                      device.name == link.peerName,
                                  onTap: () => link.connectTo(device),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('New PC? Pair it once:',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  const StepRow(1, 'Tap "Make phone visible" below.'),
                  const StepRow(2,
                      'On the PC: Settings › Bluetooth & devices › Add device '
                      '› Bluetooth, then pick this phone.'),
                  const StepRow(3, 'Confirm the code on both screens.'),
                  FilledButton.tonalIcon(
                    onPressed: visible ? null : link.makeDiscoverable,
                    icon: const Icon(Icons.bluetooth_searching, size: 18),
                    label: Text(visible
                        ? 'Visible for ${left.inMinutes}:'
                            '${(left.inSeconds % 60).toString().padLeft(2, '0')}'
                        : 'Make phone visible'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                      "Paired before but it won't connect? Remove the phone "
                      "in the PC's Bluetooth settings and pair again.",
                      style: TextStyle(color: PadColors.textDim, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile(
      {required this.device, required this.busy, required this.onTap});

  final BtDevice device;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: PadColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: Icon(
              device.isComputer ? Icons.laptop_rounded : Icons.bluetooth,
              color: device.isComputer ? PadColors.accent : PadColors.textDim),
          title: Text(device.name, overflow: TextOverflow.ellipsis),
          subtitle: device.isComputer ? null : const Text('Not a computer'),
          trailing: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
