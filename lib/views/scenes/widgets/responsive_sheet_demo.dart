import 'package:flutter/material.dart';

enum SheetPlacement { bottom, right }

class ResponsiveSheetDemo extends StatefulWidget {
  const ResponsiveSheetDemo({super.key});

  @override
  State<ResponsiveSheetDemo> createState() => _ResponsiveSheetDemoState();
}

class _ResponsiveSheetDemoState extends State<ResponsiveSheetDemo> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final isWide = constraints.maxWidth >= 900; // your breakpoint
        final placement = isWide ? SheetPlacement.right : SheetPlacement.bottom;

        return Scaffold(
          appBar: AppBar(title: const Text('Responsive Sheet')),
          body: Stack(
            children: [
              // Your main content
              ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: 40,
                itemBuilder: (_, i) => ListTile(title: Text('Item $i')),
              ),

              // The animated sheet host
              _SheetHost(
                open: _open,
                placement: placement,
                child: const _SheetContent(),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => setState(() => _open = !_open),
            label: Text(_open ? 'Close Panel' : 'Open Panel'),
            icon: Icon(_open ? Icons.close : Icons.open_in_new),
          ),
        );
      },
    );
  }
}

class _SheetHost extends StatelessWidget {
  const _SheetHost({
    required this.open,
    required this.placement,
    required this.child,
  });

  final bool open;
  final SheetPlacement placement;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Sizes for each placement
    final mq = MediaQuery.of(context);
    final bottomHeight = mq.size.height * 0.40; // 40% tall on phones
    const rightWidth = 380.0; // fixed width side sheet

    // Where the panel aligns from/to
    final beginAlign = placement == SheetPlacement.bottom
        ? Alignment.bottomCenter
        : Alignment.centerRight;

    // Target size constraints
    final targetSize = placement == SheetPlacement.bottom
        ? Size(mq.size.width, bottomHeight)
        : Size(rightWidth, mq.size.height);

    // Barrier for small screens only
    final showBarrier = placement == SheetPlacement.bottom && open;

    return IgnorePointer(
      ignoring: !open, // let taps fall through when closed
      child: Stack(
        children: [
          // Scrim barrier (optional)
          AnimatedOpacity(
            opacity: showBarrier ? 0.35 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: GestureDetector(
              onTap: () {
                // Intentionally left empty; parent can close via callback
                // or lift "open" state up and pass a closer.
              },
              child: AbsorbPointer(
                absorbing: !showBarrier,
                child: Container(color: Colors.black),
              ),
            ),
          ),

          // The panel itself
          AnimatedAlign(
            alignment: beginAlign,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              width: open ? targetSize.width : 0,
              height: open ? targetSize.height : 0,
              constraints: BoxConstraints(
                maxWidth: targetSize.width,
                maxHeight: targetSize.height,
              ),
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: open ? child : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetContent extends StatelessWidget {
  const _SheetContent();

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Column(
        children: [
          const ListTile(
            title: Text('Panel'),
            subtitle: Text('This persists and animates between layouts'),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: 25,
              itemBuilder: (_, i) => Card(
                child: ListTile(
                  title: Text('Detail row $i'),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
