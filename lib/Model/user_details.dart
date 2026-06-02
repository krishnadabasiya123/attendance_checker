import 'package:equatable/equatable.dart';

class UserDetails extends Equatable {
  final String name;
  final String email;
  final bool isClockedIn;

  const UserDetails({
    required this.name,
    required this.email,
    required this.isClockedIn,
  });

  UserDetails copyWith({
    String? name,
    String? email,
    bool? isClockedIn,
  }) {
    return UserDetails(
      name: name ?? this.name,
      email: email ?? this.email,
      isClockedIn: isClockedIn ?? this.isClockedIn,
    );
  }

  factory UserDetails.fromJson(Map<String, dynamic> json) {
    return UserDetails(
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      isClockedIn: json['isClockedIn'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'isClockedIn': isClockedIn,
  };

  @override
  List<Object?> get props => [name, email, isClockedIn];
}
