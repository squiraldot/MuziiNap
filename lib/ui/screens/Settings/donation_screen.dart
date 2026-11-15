import 'package:flutter/material.dart';

/// A compact, playful donation page using MuziiNap's shared text theme.
/// Payment processing is intentionally not connected yet.
class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key});

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {
  static const Color _background = Colors.black;
  static const Color _primaryText = Colors.white;
  static const Color _secondaryText = Color(0xFFB3B3B3);
  static const Color _border = Color(0xFF383838);

  static const List<_MealOption> _meals = [
    _MealOption(amount: 29, title: 'Choti Fries', emoji: '🍟'),
    _MealOption(amount: 59, title: 'Cold Drink', emoji: '🥤'),
    _MealOption(amount: 99, title: 'Burger', emoji: '🍔'),
    _MealOption(amount: 199, title: 'Full Meal', emoji: '🍕'),
  ];

  final TextEditingController _customAmountController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  int? _selectedAmount = 99;
  bool _monthlySupport = false;

  @override
  void dispose() {
    _customAmountController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _selectMeal(int amount) {
    setState(() {
      _selectedAmount = amount;
      _customAmountController.clear();
    });
  }

  void _onCustomAmountChanged(String value) {
    setState(() => _selectedAmount = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _primaryText,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Support Us',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            color: const Color(0xFF171717),
            onSelected: (value) {
              if (value == 'close') Navigator.maybePop(context);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'close', child: Text('Close')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            _buildHero(textTheme),
            const SizedBox(height: 12),
            _buildDivider(),
            const SizedBox(height: 14),
            Text(
              'Choose Our Next Meal 🍟',
              style: textTheme.titleMedium?.copyWith(
                color: _primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Pick a meal to keep the code (and us) running! 😅',
              style: textTheme.bodyMedium?.copyWith(color: _secondaryText),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _meals.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                mainAxisExtent: 58,
              ),
              itemBuilder: (context, index) {
                final meal = _meals[index];
                return _MealCard(
                  meal: meal,
                  selected: _selectedAmount == meal.amount,
                  onTap: () => _selectMeal(meal.amount),
                );
              },
            ),
            const SizedBox(height: 10),
            _buildCustomAmount(textTheme),
            const SizedBox(height: 16),
            Text(
              'How Often Will You Feed Us? 😂',
              style: textTheme.titleMedium?.copyWith(
                color: _primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _FrequencyOption(
                    title: 'One-time Donation',
                    selected: !_monthlySupport,
                    onTap: () => setState(() => _monthlySupport = false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FrequencyOption(
                    title: 'Monthly Support',
                    selected: _monthlySupport,
                    onTap: () => setState(() => _monthlySupport = true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Leave a Message for These Hungry Humans 💌',
              style: textTheme.titleMedium?.copyWith(
                color: _primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '(Optional)',
              style: textTheme.bodyMedium?.copyWith(color: _secondaryText),
            ),
            const SizedBox(height: 8),
            _buildMessageField(textTheme),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                // Intentionally a no-op until payment is implemented.
                onPressed: () {},
                style: FilledButton.styleFrom(
                  backgroundColor: _primaryText,
                  foregroundColor: Colors.black,
                  shape: const StadiumBorder(),
                  textStyle: textTheme.bodyLarge?.copyWith(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Feed These Hungry Devs 🍔'),
                    SizedBox(width: 10),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_rounded, color: _secondaryText, size: 13),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Secure Payment • UPI, Cards, Wallets & More',
                    style: textTheme.bodySmall?.copyWith(color: _secondaryText),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(TextTheme textTheme) {
    return Column(
      children: [
        SizedBox(
          height: 112,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 12,
                bottom: 14,
                child: _FoodEmoji('🍔', size: 34),
              ),
              Positioned(
                right: 12,
                bottom: 16,
                child: _FoodEmoji('🥤', size: 32),
              ),
              Positioned(
                top: 0,
                child: Image.asset(
                  'assets/icons/icon.png',
                  width: 108,
                  height: 108,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text('🐿️', style: TextStyle(fontSize: 72)),
                ),
              ),
              const Positioned(
                left: 64,
                top: 14,
                child: Text('✦', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
              const Positioned(
                right: 58,
                top: 20,
                child: Text('✧', style: TextStyle(color: Colors.white, fontSize: 17)),
              ),
            ],
          ),
        ),
        Text(
          'Feed Our Developers😝\n(Burgerrrr🍔)',
          textAlign: TextAlign.center,
          style: textTheme.titleLarge?.copyWith(
            color: _primaryText,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          "We're Hungry but our Pocket is Lonely😭",
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge?.copyWith(
            color: _primaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: _secondaryText, thickness: 1)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('🍔', style: TextStyle(fontSize: 17)),
        ),
        const Expanded(child: Divider(color: _secondaryText, thickness: 1)),
      ],
    );
  }

  Widget _buildCustomAmount(TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(
          color: _customAmountController.text.isNotEmpty ? Colors.white : _border,
          width: _customAmountController.text.isNotEmpty ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, color: _primaryText, size: 21),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Custom Amount',
                  style: textTheme.bodyLarge?.copyWith(
                    color: _primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Enter your own amount',
                  style: textTheme.bodySmall?.copyWith(color: _secondaryText),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 88,
            child: TextField(
              key: const Key('custom-donation-amount'),
              controller: _customAmountController,
              onChanged: _onCustomAmountChanged,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: textTheme.bodyLarge?.copyWith(
                color: _primaryText,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: textTheme.bodyLarge?.copyWith(color: _primaryText),
                hintText: '0',
                hintStyle: textTheme.bodyLarge?.copyWith(color: _secondaryText),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _secondaryText),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _primaryText, width: 1.3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageField(TextTheme textTheme) {
    return TextField(
      key: const Key('donation-message'),
      controller: _messageController,
      maxLength: 200,
      maxLines: 2,
      minLines: 2,
      style: textTheme.bodyMedium?.copyWith(color: _primaryText),
      decoration: InputDecoration(
        hintText: 'Say something before we eat your money... 😂',
        hintStyle: textTheme.bodyMedium?.copyWith(color: _secondaryText),
        counterText: '${_messageController.text.length} / 200',
        counterStyle: textTheme.bodySmall?.copyWith(color: _secondaryText),
        filled: true,
        fillColor: const Color(0xFF080808),
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _primaryText, width: 1.3),
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }
}

class _MealOption {
  const _MealOption({
    required this.amount,
    required this.title,
    required this.emoji,
  });

  final int amount;
  final String title;
  final String emoji;

  String get label => '₹$amount $title $emoji';
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.meal,
    required this.selected,
    required this.onTap,
  });

  final _MealOption meal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: meal.label,
      child: Material(
        color: const Color(0xFF080808),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected ? Colors.white : const Color(0xFF383838),
                width: selected ? 1.7 : 1,
              ),
            ),
            child: Row(
              children: [
                Text(meal.emoji, style: const TextStyle(fontSize: 23)),
                const SizedBox(width: 6),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      meal.label,
                      maxLines: 1,
                      softWrap: false,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 3),
                  const Icon(Icons.check_circle, color: Colors.white, size: 15),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FrequencyOption extends StatelessWidget {
  const _FrequencyOption({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: selected ? Colors.white : Colors.black,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? Colors.white : const Color(0xFFB3B3B3),
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? Colors.black : Colors.white,
                size: 17,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    style: textTheme.bodyMedium?.copyWith(
                      color: selected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodEmoji extends StatelessWidget {
  const _FoodEmoji(this.emoji, {required this.size});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(emoji, style: TextStyle(fontSize: size));
  }
}
