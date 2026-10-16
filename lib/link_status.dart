import 'package:flutter/material.dart';

import 'connect_sheets.dart';
import 'links/bluetooth_link.dart';
import 'links/pad_link.dart';
import 'pad_controller.dart';
import 'pad_theme.dart';

/// The connection as the user sees it: a color, a few words, and the next
/// thing to do (if any).
class LinkStatus {
  const LinkStatus({
    required this.color,
    required this.title,
    required this.detail,
    this.connected = false,
    this.busy = false,
    this.action,
    this.onAction,
  });

  final Color color;
  final String title;
  final String detail;
  final bool connected;
  final bool busy;
  final String? action;
  final VoidCallback? onAction;
}

LinkStatus describeLink(BuildContext context, PadController controller) {
  final link = controller.link;
  if (link.connected) {
    return LinkStatus(
      color: PadColors.connected,
      title: 'Connected to ${link.peerName ?? 'your PC'}',
      detail: link is BluetoothLink ? 'Over Bluetooth' : 'Over the USB cable',
      connected: true,
    );
  }
  if (link is! BluetoothLink) {
    return LinkStatus(
      color: PadColors.waiting,
      title: 'Waiting for your PC',
      detail: 'Plug in the USB cable and open Mouse Pad Receiver on the PC',
      busy: true,
      action: 'How to connect',
      onAction: () => showUsbHelp(context),
    );
  }
  return switch (link.phase) {
    BtPhase.ready => LinkStatus(
        color: PadColors.waiting,
        title: 'Not connected',
        detail: link.message ?? 'Pick your PC, or pair a new one',
        action: 'Choose PC',
        onAction: () => showBluetoothPicker(context, link),
      ),
    BtPhase.connecting => LinkStatus(
        color: PadColors.waiting,
        title: 'Connecting to ${link.peerName ?? 'your PC'}…',
        detail: "Make sure the PC's Bluetooth is on",
        busy: true,
      ),
    BtPhase.reconnecting => LinkStatus(
        color: PadColors.waiting,
        title: 'Reconnecting to ${link.peerName ?? 'your PC'}…',
        detail: "This happens by itself. Make sure the PC's Bluetooth is on",
        busy: true,
        action: 'Choose PC',
        onAction: () => showBluetoothPicker(context, link),
      ),
    BtPhase.idle || BtPhase.starting || BtPhase.connected =>
      const LinkStatus(
        color: PadColors.waiting,
        title: 'Starting Bluetooth…',
        detail: 'Getting the touchpad ready',
        busy: true,
      ),
    BtPhase.bluetoothOff => LinkStatus(
        color: PadColors.waiting,
        title: 'Bluetooth is off',
        detail: 'Turn it on to connect to your PC',
        action: 'Turn on',
        onAction: link.enableBluetooth,
      ),
    BtPhase.needsPermission => LinkStatus(
        color: PadColors.waiting,
        title: 'Permission needed',
        detail: link.message ?? 'Allow "Nearby devices" to use Bluetooth',
        action: 'Allow',
        onAction: link.retry,
      ),
    BtPhase.unsupported => LinkStatus(
        color: PadColors.danger,
        title: 'Bluetooth not available',
        detail: link.message ?? 'Use the USB cable instead',
        action: 'Use USB',
        onAction: () => controller.settings.mode = LinkMode.usb,
      ),
    BtPhase.error => LinkStatus(
        color: PadColors.danger,
        title: 'Bluetooth stopped',
        detail: link.message ?? 'Something went wrong',
        action: 'Try again',
        onAction: link.retry,
      ),
  };
}

/// One line of status: dot, words, and the next step as a button.
class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.status});

  final LinkStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        StatusDot(color: status.color, pulsing: !status.connected),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(status.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(status.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: PadColors.textDim, fontSize: 12.5)),
            ],
          ),
        ),
        if (status.action != null) ...[
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: status.onAction,
            child: Text(status.action!),
          ),
        ],
      ],
    );
  }
}

/// Covers the touchpad while it isn't connected.
class NotConnectedOverlay extends StatelessWidget {
  const NotConnectedOverlay({super.key, required this.status});

  final LinkStatus status;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PadColors.background.withValues(alpha: 0.86),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status.busy)
                const SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
              else
                Icon(Icons.link_off_rounded, color: status.color, size: 32),
              const SizedBox(height: 14),
              Text(status.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(status.detail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: PadColors.textDim)),
              ),
              if (status.action != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: status.onAction, child: Text(status.action!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
