import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { admin, pilota }

class UserModel {
  final String id;
  final String email;
  final String nome;
  final String cognome;
  final UserRole role;
  final DateTime createdAt;
  final String? preferredTeamName;
  final String? photoUrl;

  /// Stato account (Step 42, elenco utenti admin): true = attivo (default),
  /// false = disabilitato dall'admin. Non esisteva prima un flusso di
  /// approvazione registrazioni nell'app — questo campo è la sola nozione
  /// di "stato account" introdotta, non un'approvazione a due stati.
  final bool attivo;

  const UserModel({
    required this.id,
    required this.email,
    required this.nome,
    required this.cognome,
    required this.role,
    required this.createdAt,
    this.preferredTeamName,
    this.photoUrl,
    this.attivo = true,
  });

  String get nomeCompleto => '$nome $cognome';

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      email: d['email'] ?? '',
      nome: d['nome'] ?? '',
      cognome: d['cognome'] ?? '',
      role: d['role'] == 'admin' ? UserRole.admin : UserRole.pilota,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      preferredTeamName: d['preferredTeamName'] as String?,
      photoUrl: d['photoUrl'] as String?,
      attivo: d['attivo'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'email': email,
        'nome': nome,
        'cognome': cognome,
        'role': role.name,
        'createdAt': Timestamp.fromDate(createdAt),
        if (preferredTeamName != null) 'preferredTeamName': preferredTeamName,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'attivo': attivo,
      };

  UserModel copyWith({
    String? id,
    String? email,
    String? nome,
    String? cognome,
    UserRole? role,
    String? preferredTeamName,
    String? photoUrl,
    bool clearPhotoUrl = false,
    bool? attivo,
  }) =>
      UserModel(
        id: id ?? this.id,
        email: email ?? this.email,
        nome: nome ?? this.nome,
        cognome: cognome ?? this.cognome,
        role: role ?? this.role,
        createdAt: createdAt,
        preferredTeamName: preferredTeamName ?? this.preferredTeamName,
        photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
        attivo: attivo ?? this.attivo,
      );
}
