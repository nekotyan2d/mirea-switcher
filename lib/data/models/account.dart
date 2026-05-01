class Account {
  final String name;
  final String token;

  const Account({required this.name, required this.token});

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    name: json['name'] as String,
    token: json['token'] as String,
  );

  Map<String, dynamic> toJson() => {'name': name, 'token': token};

  @override
  bool operator ==(Object other) {
    return other is Account && other.token == token && other.name == name;
  }

  @override
  int get hashCode => Object.hash(name, token);
}