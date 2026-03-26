import 'package:flutter/material.dart';
import 'package:meet/constants/app.config.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/button.inline.dart';
import 'package:meet/views/scenes/core/view.dart';
import 'package:meet/views/scenes/home.meet/home.viewmodel.dart';

class HomeView extends ViewBase<HomeViewModel> {
  const HomeView(HomeViewModel viewModel)
    : super(viewModel, const Key("HomeView"));

  @override
  Widget build(BuildContext context) {
    return buildMain(context);
  }

  Widget buildMain(BuildContext context) {
    return buildPage(context);
  }
}

Widget buildPage(BuildContext context) {
  return Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height,
            minWidth: MediaQuery.of(context).size.width,
          ),
          child: IntrinsicHeight(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Proton Meet',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Colors.deepPurple,
                        ),
                      ),
                      Row(
                        children: [
                          ButtonInline(
                            text: 'Schedule Meeting',
                            onPressed: () {},
                            width: 180,
                            height: 50,
                            borderRadius: 40,
                            textColor: Colors.white,
                            backgroundColor: context.colors.protonBlue,
                          ),
                          SizedBox(width: 12),
                          ButtonInline(
                            text: 'Start Meeting',
                            onPressed: () {},
                            width: 180,
                            height: 50,
                            borderRadius: 40,
                            textColor: context.colors.textNorm,
                            backgroundColor: context.colors.backgroundSecondary,
                          ),
                          SizedBox(width: 12),
                          Icon(Icons.notifications),
                          SizedBox(width: 8),
                          Icon(Icons.account_circle),
                        ],
                      ),
                    ],
                  ),
                ),

                // Body
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Sidebar
                        Column(
                          children: [
                            Icon(Icons.home),
                            SizedBox(height: 16),
                            Icon(Icons.calendar_today),
                            SizedBox(height: 16),
                            Icon(Icons.chat),
                            SizedBox(height: 16),
                            Icon(Icons.settings),
                            SizedBox(height: 16),
                            Icon(Icons.flash_on),
                          ],
                        ),
                        SizedBox(width: 24),

                        // Main Content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.local.upcoming_meetings,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 12),
                              _buildMeetingCard(
                                context,
                                title: "Weekly Standup",
                                subtitle:
                                    "Mon, 10:00 AM · 3 participants · Proton Calendar",
                                tags: ["Waiting Room", "Password Protected"],
                              ),
                              _buildMeetingCard(
                                context,
                                title: "Design Review",
                                subtitle:
                                    "Tue, 2:00 PM · 5 participants · Google Calendar",
                                tags: ["Waiting Room"],
                              ),
                              _buildMeetingCard(
                                context,
                                title: "Client Call",
                                subtitle:
                                    "Wed, 4:30 PM · 2 participants · Outlook",
                                tags: [],
                              ),
                              SizedBox(height: 24),
                              Text(
                                "Recent Meetings",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 12),
                              _buildMeetingCard(
                                context,
                                title: "Team Brainstorm",
                                subtitle:
                                    "Yesterday, 3:30 PM · 45 min · 6 participants",
                                tags: ["Recording", "Repeat"],
                              ),
                              _buildMeetingCard(
                                context,
                                title: "Weekly Standup",
                                subtitle:
                                    "Mon, May 20 · 31 min · 4 participants",
                                tags: ["Notes", "Repeat"],
                              ),
                            ],
                          ),
                        ),

                        // Right Instant Meeting Box
                        SizedBox(width: 24),
                        Container(
                          width: 240,
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: context.colors.backgroundSecondary,
                          ),
                          child: Column(
                            children: [
                              Text(
                                "Start Instant Meeting",
                                style: ProtonStyles.body2Medium(
                                  color: context.colors.textNorm,
                                ),
                              ),
                              SizedBox(height: 12),
                              TextField(
                                controller: TextEditingController(
                                  text: "${appConfig.apiEnv.baseUrl}/your-link",
                                ),
                                style: ProtonStyles.body2Regular(
                                  color: context.colors.protonBlue,
                                ),
                                readOnly: true,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              SizedBox(height: 12),
                              ButtonInline(
                                text: 'Copy Link',
                                onPressed: () {},
                                width: 120,
                                height: 50,
                                borderRadius: 40,
                                textColor: context.colors.textNorm,
                                backgroundColor:
                                    context.colors.backgroundSecondary,
                              ),
                              SizedBox(height: 8),
                              ButtonInline(
                                text: 'Start Now',
                                onPressed: () {},
                                width: 120,
                                height: 50,
                                borderRadius: 40,
                                textColor: Colors.white,
                                backgroundColor: context.colors.protonBlue,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _buildMeetingCard(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<String> tags,
}) {
  return Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          Icon(Icons.calendar_today, size: 32),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(subtitle, style: TextStyle(color: Colors.grey[700])),
                Wrap(
                  spacing: 8,
                  children: tags
                      .map(
                        (tag) => Chip(
                          label: Text(tag),
                          backgroundColor: context.colors.backgroundSecondary,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          ButtonInline(
            text: 'Details',
            onPressed: () {},
            width: 100,
            height: 50,
            borderRadius: 40,
            textColor: context.colors.textNorm,
            backgroundColor: context.colors.backgroundSecondary,
          ),
          SizedBox(width: 8),
          ButtonInline(
            text: 'Start',
            onPressed: () {},
            width: 100,
            height: 50,
            borderRadius: 40,
            textColor: Colors.white,
            backgroundColor: context.colors.protonBlue,
          ),
        ],
      ),
    ),
  );
}
