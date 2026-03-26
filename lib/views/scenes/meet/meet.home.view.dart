import 'package:flutter/material.dart';
import 'package:meet/views/scenes/core/view.dart';
import 'package:meet/views/scenes/meet/meet.home.viewmodel.dart';

class MeetHomeView extends ViewBase<MeetHomeViewModel> {
  const MeetHomeView(MeetHomeViewModel viewModel, {super.locker})
    : super(viewModel, const Key("/MeetHomeView"));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: viewModel.requestPermissions(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show a loading spinner while waiting
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            // Handle potential errors
            return Center(
              child: Text('Error requesting permissions: ${snapshot.error}'),
            );
          } else {
            // Show PreJoinPage when permissions are granted (or future completes without error)
            return Text("MeetHomeView");
          }
        } else {
          // Handle other states if necessary, or just show loading
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}
