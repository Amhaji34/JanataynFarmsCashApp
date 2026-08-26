import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class PartnersScreen extends StatefulWidget {
  const PartnersScreen({super.key});

  @override
  State<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends State<PartnersScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _partners = [];

  final _nameController = TextEditingController();
  bool _adding = false;
  String? _addError;

  @override
  void initState() {
    super.initState();
    _loadPartners();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadPartners() async {
    setState(() => _loading = true);
    try {
      final data = await supabase.from('partners').select().order('name');
      setState(() {
        _partners = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load partners: $e';
        _loading = false;
      });
    }
  }

  Future<void> _addPartner() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _adding = true;
      _addError = null;
    });
    try {
      await supabase.from('partners').insert({'name': name});
      _nameController.clear();
      await _loadPartners();
    } catch (e) {
      setState(() => _addError = 'Could not add partner: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partners')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('ADD A PARTNER'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            hintText: 'Partner name',
                            isDense: true,
                            prefixIcon: Icon(
                              Icons.person_add_alt_outlined,
                              size: 19,
                              color: AppColors.inkMuted,
                            ),
                          ),
                          onSubmitted: (_) => _addPartner(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _adding ? null : _addPartner,
                          child: _adding
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Add'),
                        ),
                      ),
                    ],
                  ),
                  if (_addError != null) ...[
                    const SizedBox(height: 12),
                    ErrorNote(_addError!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (!_loading && _errorMessage == null && _partners.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: SectionLabel(
                  'PARTNERS',
                  trailing: Text(
                    '${_partners.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                  ? Center(child: ErrorNote(_errorMessage!))
                  : _partners.isEmpty
                  ? const EmptyState(
                      icon: Icons.handshake_outlined,
                      title: 'No partners yet',
                      subtitle:
                          'Add your colleagues here so you can record loans '
                          'and repayments against them.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: _partners.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final name = _partners[index]['name'] as String;
                        return AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              InitialsAvatar(name: name),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
