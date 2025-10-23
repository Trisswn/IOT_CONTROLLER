import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'smart_home_state.dart';
import 'profile_model.dart';
import 'profile_edit_screen.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<SmartHomeState>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Perfiles de Usuario"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const ProfileEditScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: state.profiles.length,
        itemBuilder: (ctx, index) {
          final profile = state.profiles[index];
          return ListTile(
            title: Text(profile.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                     Navigator.of(context).push(
                       MaterialPageRoute(builder: (ctx) => ProfileEditScreen(profileIndex: index)),
                     );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => state.deleteProfile(index),
                ),
              ],
            ),
            onTap: () {
              state.setActiveProfile(profile);
              Navigator.of(context).pop(); // Vuelve a la pantalla principal
            },
          );
        },
      ),
    );
  }
}