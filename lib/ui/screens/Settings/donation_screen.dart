import 'package:flutter/material.dart';

/// A compact, playful donation page for the MuziiNap team.
/// Payment processing is intentionally not connected yet.
class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key});

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {

  static const List<_MealOption> _meals = [
    _MealOption(amount: 29, title: 'Choti Fries', emoji: '🍟'),
    _MealOption(amount: 59, title: 'Cold Drink', emoji: '🥤'),
    _MealOption(amount: 99, title: 'Burger', emoji: '🍔'),
    _MealOption(amount: 199, title: 'Full Meal', emoji: '🍕'),
  ];

  final TextEditingController _customAmountController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  int? _selectedAmount = 99;

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
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        title: const Text('Support Us'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: theme.dividerColor),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            _buildHero(textTheme),
            const SizedBox(height: 12),
            _buildDivider(theme),
            const SizedBox(height: 14),
            Text(
              'Choose Our Next Meal 🍟',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Pick a meal to keep the code (and us) running! 😅',
              style: textTheme.bodyMedium,
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
            _buildCustomAmount(theme),
            const SizedBox(height: 16),
            Text(
              'Leave a Message for These Hungry Humans 💌',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '(Optional)',
              style: textTheme.bodyMedium,
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
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: const StadiumBorder(),
                  textStyle: textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onPrimary,
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
                Icon(Icons.lock_rounded, color: theme.colorScheme.onSurface, size: 13),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Secure Payment • UPI, Cards, Wallets & More',
                    style: textTheme.bodySmall,
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
    final primaryTextColor = textTheme.titleLarge?.color ?? Theme.of(context).colorScheme.onSurface;
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
                  errorBuilder: (_, __, ___) =>
                      const Text('🐿️', style: TextStyle(fontSize: 72)),
                ),
              ),
              Positioned(
                left: 64,
                top: 14,
                child: Text('✦', style: TextStyle(color: primaryTextColor, fontSize: 16)),
              ),
              Positioned(
                right: 58,
                top: 20,
                child: Text('✧', style: TextStyle(color: primaryTextColor, fontSize: 17)),
              ),
            ],
          ),
        ),
        Text(
          'Feed Our Developers😝\n(Burgerrrr🍔)',
          textAlign: TextAlign.center,
          style: textTheme.titleLarge?.copyWith(
            color: primaryTextColor,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          "We're Hungry but our Pocket is Lonely😭",
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge?.copyWith(
            color: textTheme.bodyLarge?.color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Row(
      children: [
        Expanded(child: Divider(color: theme.dividerColor, thickness: 1)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('🍔', style: TextStyle(fontSize: 17)),
        ),
        Expanded(child: Divider(color: theme.dividerColor, thickness: 1)),
      ],
    );
  }

  Widget _buildCustomAmount(ThemeData theme) {
    final textTheme = theme.textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(
          color: _customAmountController.text.isNotEmpty ? theme.colorScheme.primary : theme.dividerColor,
          width: _customAmountController.text.isNotEmpty ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_outlined, color: theme.colorScheme.onSurface, size: 21),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Custom Amount',
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Enter your own amount',
                  style: textTheme.bodySmall,
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
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: textTheme.bodyLarge,
                hintText: '0',
                hintStyle: textTheme.bodyLarge,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageField(TextTheme textTheme) {
    final theme = Theme.of(context);
    return TextField(
      key: const Key('donation-message'),
      controller: _messageController,
      maxLength: 200,
      maxLines: 2,
      minLines: 2,
      style: textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Say something before we eat your money... 😂',
        hintStyle: textTheme.bodyMedium,
        counterText: '${_messageController.text.length} / 200',
        counterStyle: textTheme.bodySmall,
        filled: true,
        fillColor: theme.cardColor,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: theme.dividerColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.3),
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

  String get label => '₹$amount $title';
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
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: meal.label,
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected ? theme.colorScheme.primary : theme.dividerColor,
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
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 3),
                  Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 15),
                ],
              ],
            ),
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
