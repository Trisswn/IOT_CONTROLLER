import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'smart_home_state.dart';
import 'profile_model.dart';
import 'profile_edit_screen.dart';
import 'app_colors.dart'; // <<< IMPORTAR NUEVOS COLORES

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<SmartHomeState>(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        // El estilo se toma del theme
        title: const Text("Perfiles de Usuario"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline), // Icono actualizado
            color: AppColors.primary, // Darle el color primario
            iconSize: 28,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const ProfileEditScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Añadir padding
        itemCount: state.profiles.length,
        itemBuilder: (ctx, index) {
          final profile = state.profiles[index];
          // --- ENVOLVER EL LISTTILE EN UNA CARD ---
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6), // Espacio entre tarjetas
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              title: Text(profile.name, style: textTheme.titleMedium),
              leading: const Icon(Icons.person_outline, color: AppColors.primary),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
                    onPressed: () {
                       Navigator.of(context).push(
                         MaterialPageRoute(builder: (ctx) => ProfileEditScreen(profileIndex: index)),
                       );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.accentRed),
                    onPressed: () => state.deleteProfile(index),
                  ),
                ],
              ),
              onTap: () {
                state.setActiveProfile(profile);
                Navigator.of(context).pop(profile); // Vuelve a la pantalla principal
              },
            ),
          );
        },
      ),
    );
  }
}