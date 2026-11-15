import 'package:flutter/material.dart';

/// A playful, AMOLED-black donation page for the MuziiNap team.
///
/// Payment processing is intentionally not connected yet. The primary CTA is
/// present for the future payment integration and currently performs no action.
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
    _MealOption(
      amount: 29,
      title: 'Choti Fries',
      subtitle: 'Tiny happiness',
      emoji: '🍟',
    ),
    _MealOption(
      amount: 59,
      title: 'Cold Drink',
      subtitle: 'Refresh us',
      emoji: '🥤',
    ),
    _MealOption(
      amount: 99,
      title: 'Burger',
      subtitle: "Developer's dream",
      emoji: '🍔',
    ),
    _MealOption(
      amount: 199,
      title: 'Full Meal',
      subtitle: 'Developer feast',
      emoji: '🍕',
    ),
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
    setState(() {
      _selectedAmount = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _primaryText,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Support Us',
          style: TextStyle(fontWeight: FontWeight.w700),
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _buildHero(theme),
            const SizedBox(height: 18),
            _buildDivider(),
            const SizedBox(height: 22),
            Text(
              'Choose Our Next Meal 🍟',
              style: theme.textTheme.titleLarge?.copyWith(
                color: _primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick a meal to keep the code (and us) running! 😅',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _secondaryText,
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _meals.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 106,
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
            const SizedBox(height: 12),
            _buildCustomAmount(),
            const SizedBox(height: 24),
            Text(
              'How Often Will You Feed Us? 😂',
              style: theme.textTheme.titleLarge?.copyWith(
                color: _primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _FrequencyOption(
                    title: 'One-time Donation',
                    selected: !_monthlySupport,
                    onTap: () => setState(() => _monthlySupport = false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FrequencyOption(
                    title: 'Monthly Support',
                    selected: _monthlySupport,
                    onTap: () => setState(() => _monthlySupport = true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Leave a Message for These Hungry Humans 💌',
              style: theme.textTheme.titleMedium?.copyWith(
                color: _primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '(Optional)',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _secondaryText,
              ),
            ),
            const SizedBox(height: 10),
            _buildMessageField(),
            const SizedBox(height: 22),
            SizedBox(
              height: 58,
              child: FilledButton(
                // Intentionally left as a no-op until payment is implemented.
                onPressed: () {},
                style: FilledButton.styleFrom(
                  backgroundColor: _primaryText,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: _primaryText,
                  disabledForegroundColor: Colors.black,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Feed These Hungry Devs 🍔'),
                    SizedBox(width: 12),
                    Icon(Icons.arrow_forward_rounded, size: 23),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_rounded, color: _secondaryText, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Secure Payment • UPI, Cards, Wallets & More',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _secondaryText,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(ThemeData theme) {
    return Column(
      children: [
        SizedBox(
          height: 190,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 10,
                bottom: 26,
                child: _FoodEmoji('🍔', size: 54),
              ),
              Positioned(
                right: 10,
                bottom: 30,
                child: _FoodEmoji('🥤', size: 48),
              ),
              Positioned(
                top: 4,
                child: Image.asset(
                  'assets/icons/icon.png',
                  width: 164,
                  height: 164,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text('🐿️', style: TextStyle(fontSize: 112)),
                ),
              ),
              const Positioned(
                left: 76,
                top: 24,
                child: Text('✦', style: TextStyle(color: Colors.white, fontSize: 22)),
              ),
              const Positioned(
                right: 70,
                top: 34,
                child: Text('✧', style: TextStyle(color: Colors.white, fontSize: 24)),
              ),
            ],
          ),
        ),
        Text(
          'Feed Our Developers😝\n(Burgerrrr🍔)',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: _primaryText,
            fontWeight: FontWeight.w900,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "We're Hungry but our Pocket is Lonely😭",
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('🍔', style: const TextStyle(fontSize: 23)),
        ),
        const Expanded(child: Divider(color: _secondaryText, thickness: 1)),
      ],
    );
  }

  Widget _buildCustomAmount() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: _border, width: 1.2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, color: _primaryText, size: 27),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Custom Amount',
                  style: TextStyle(
                    color: _primaryText,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Enter your own amount',
                  style: TextStyle(color: _secondaryText, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 112,
            child: TextField(
              key: const Key('custom-donation-amount'),
              controller: _customAmountController,
              onChanged: _onCustomAmountChanged,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                color: _primaryText,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: const TextStyle(color: _primaryText),
                hintText: '0',
                hintStyle: const TextStyle(color: _secondaryText),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _secondaryText),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _primaryText, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageField() {
    return TextField(
      key: const Key('donation-message'),
      controller: _messageController,
      maxLength: 200,
      maxLines: 3,
      minLines: 3,
      style: const TextStyle(color: _primaryText),
      decoration: InputDecoration(
        hintText: 'Say something before we eat your money... 😂',
        hintStyle: const TextStyle(color: _secondaryText),
        counterText: '${_messageController.text.length} / 200',
        counterStyle: const TextStyle(color: _secondaryText),
        filled: true,
        fillColor: const Color(0xFF080808),
        contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: _border, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: _primaryText, width: 1.5),
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
    required this.subtitle,
    required this.emoji,
  });

  final int amount;
  final String title;
  final String subtitle;
  final String emoji;
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
    final borderColor = selected ? Colors.white : const Color(0xFF383838);
    return Semantics(
      button: true,
      selected: selected,
      label: '${meal.title}, ₹${meal.amount}',
      child: Material(
        color: const Color(0xFF080808),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: borderColor,
                width: selected ? 2.2 : 1.2,
              ),
            ),
            child: Stack(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 54,
                      child: Text(
                        meal.emoji,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 38),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '₹${meal.amount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            meal.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            meal.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB3B3B3),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (selected)
                  const Positioned(
                    right: 0,
                    top: 0,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.check_rounded, color: Colors.black, size: 16),
                    ),
                  ),
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
    return Material(
      color: selected ? Colors.white : Colors.black,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: selected ? Colors.white : const Color(0xFFB3B3B3),
              width: selected ? 1.5 : 1.1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? Colors.black : Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
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
  Widget build(BuildContext context) => Text(
        emoji,
        style: TextStyle(fontSize: size),
      );
}
