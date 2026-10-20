enum UserRole {
  owner,
  vet,
  clinic;

  bool get isProvider => this == UserRole.vet || this == UserRole.clinic;

  String toValue() {
    switch (this) {
      case UserRole.vet:
        return 'vet';
      case UserRole.clinic:
        return 'clinic';
      case UserRole.owner:
        return 'owner';
    }
  }

  String get displayName {
    switch (this) {
      case UserRole.vet:
      case UserRole.clinic:
        return 'Vet / Clinic';
      case UserRole.owner:
        return 'Pet Owner';
    }
  }

  static UserRole fromString(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'vet':
        return UserRole.vet;
      case 'clinic':
        return UserRole.clinic;
      case 'provider':
      case 'vet_clinic':
        return UserRole.vet;
      case 'owner':
      default:
        return UserRole.owner;
    }
  }
}

