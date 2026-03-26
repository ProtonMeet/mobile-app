import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meet/helper/logger.dart';

abstract class BlocView extends StatefulWidget {
  final Widget? locker;
  const BlocView(Key key, {this.locker}) : super(key: key);

  @override
  BlocViewState<BlocView> createState() {
    return BlocViewState();
  }

  String getRouteName() {
    if (kIsWeb) {
      return "/$key";
    }
    return key.toString();
  }
}

abstract class BlocProviderInterface {
  Widget buildView(BuildContext context);
}

// view base state
class BlocViewState<T extends BlocView> extends State<T>
    with AutomaticKeepAliveClientMixin<T>
    implements BlocProviderInterface {
  @override
  void dispose() {
    super.dispose();
    logger.d("${widget.key} dispose is called");
  }

  @override
  bool get wantKeepAlive {
    // keep a live, when navigation screen goes to backgroun
    return true;
  }

  @override
  void reassemble() {
    // add your logic
    super.reassemble();
    logger.i('Hot occurred : in ${widget.key}');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return buildView(context);
  }

  @override
  Widget buildView(BuildContext context) {
    throw UnimplementedError();
  }
}
