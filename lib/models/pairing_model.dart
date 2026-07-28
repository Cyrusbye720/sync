import 'package:flutter/material.dart';

/// Domain model for the Supabase `pairings` table.
///
/// One of `userA` / `userB` is always the current user; the other is the
/// partner. The `invite_code` is generated server-side and persists on the
/// row so client and server agree on the same code (see `supabase/init.sql`).
@immutable
class PairingModel {
  final String id;
  final String userA;
  final String? userB;
  final String status;
  final String? inviteCode;
  final DateTime? acceptedAt;

  const PairingModel({
    required this.id,
    required this.userA,
    required this.userB,
    required this.status,
    required this.inviteCode,
    required this.acceptedAt,
  });

  static const String pending = 'pending';
  static const String accepted = 'accepted';
  static const String blocked = 'blocked';

  bool get isAccepted => status == accepted;
  bool get isPending => status == pending;

  String partnerId(String currentUserId) {
    final other = userA == currentUserId ? userB : userA;
    if (other == null) return currentUserId; // partner not joined yet
    return other;
  }

  factory PairingModel.fromMap(Map<String, dynamic> map) {
    return PairingModel(
      id: map['id'] as String,
      userA: map['user_a'] as String,
      userB: map['user_b'] as String?,
      status: (map['status'] as String?) ?? pending,
      inviteCode: map['invite_code'] as String?,
      acceptedAt: map['accepted_at'] == null
          ? null
          : DateTime.parse(map['accepted_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'user_a': userA,
      'user_b': userB,
      'status': status,
      'invite_code': inviteCode,
      'accepted_at': acceptedAt?.toIso8601String(),
    };
  }
}
