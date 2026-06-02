import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../Model/user_details.dart';
import '../../utiils/hive_constant.dart';

@immutable
sealed class UserDetailsState {}

final class UserDetailsInitial extends UserDetailsState {}

final class UserDetailsLoading extends UserDetailsState {}

final class UserDetailsLoaded extends UserDetailsState {
  final UserDetails user;
  UserDetailsLoaded({required this.user});
}

final class UserDetailsError extends UserDetailsState {
  final String message;
  UserDetailsError({required this.message});
}

class UserDetailsCubit extends Cubit<UserDetailsState> {
  UserDetailsCubit() : super(UserDetailsInitial());

  // Fetch user details from Hive or initialize mock data
  void fetchUserDetails() {
    emit(UserDetailsLoading());
    try {
      final box = Hive.box<dynamic>(authBox);
      final rawData = box.get(userDetailsKey);

      if (rawData != null) {
        // Parse from stored Map
        final map = Map<String, dynamic>.from(rawData as Map);
        final user = UserDetails.fromJson(map);
        emit(UserDetailsLoaded(user: user));
      } else {
        // Create mock user details for testing if none exist in Hive
        final mockUser = const UserDetails(
          name: "Shree",
          email: "shree@example.com",
          isClockedIn: false,
        );
        // Persist mock user details to Hive authBox
        box.put(userDetailsKey, mockUser.toJson());
        emit(UserDetailsLoaded(user: mockUser));
      }
    } catch (e) {
      emit(
        UserDetailsError(
          message: "Failed to fetch user details: ${e.toString()}",
        ),
      );
    }
  }

  // Update clock-in/out status in the user details model and persist to Hive
  Future<void> updateClockStatus(bool isClockedIn) async {
    final currentState = state;
    if (currentState is UserDetailsLoaded) {
      try {
        final updatedUser = currentState.user.copyWith(
          isClockedIn: isClockedIn,
        );
        final box = Hive.box<dynamic>(authBox);

        // Save back to Hive authBox
        await box.put(userDetailsKey, updatedUser.toJson());

        emit(UserDetailsLoaded(user: updatedUser));
      } catch (e) {
        emit(
          UserDetailsError(
            message: "Failed to update user clock status: ${e.toString()}",
          ),
        );
      }
    }
  }
}
