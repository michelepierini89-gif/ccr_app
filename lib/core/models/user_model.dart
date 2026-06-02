import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { admin, pilota }

class UserModel {
  final String id;
  final String email;
  final String nome;
  final String cognome;
  final UserRole role;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.email,
    required this.nome,
    required this.cognome,
    required this.role,
    required this.createdAt,
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
    );
  }

  Map<String, dynamic> toFirestore() => {
        'email': email,
        'nome': nome,
        'cognome': cognome,
        'role': role.name,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  UserModel copyWith({
    String? id,
    String? email,
    String? nome,
    String? cognome,
    UserRole? role,
  }) =>
      UserModel(
        id: id ?? this.id,
        email: email ?? this.email,
        nome: nome ?? this.nome,
        cognome: cognome ?? this.cognome,
        role: role ?? this.role,
        createdAt: createdAt,
      );
}
