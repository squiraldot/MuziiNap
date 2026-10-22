import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

///ignore: must_be_immutable
class SideBarAnimated extends StatefulWidget {
  final ValueChanged<int>? onTap;
  final ValueChanged<int>? onLongPress;
  Color sideBarColor;
  Duration sideBarAnimationDuration;
  Duration floatingAnimationDuration;
  Color animatedContainerColor;
  Color selectedIconColor;
  Color unselectedIconColor;
  Color dividerColor;
  Color hoverColor;
  Color splashColor;
  Color highlightColor;
  Color unSelectedTextColor;
  double widthSwitch;
  double borderRadius;
  double sideBarWidth;
  // double sideBarItemHeight;
  double sideBarSmallWidth;
  String mainLogoImage;
  List<SideBarItem> sidebarItems;
  bool settingsDivider;
  Curve curve;
  TextStyle textStyle;

  SideBarAnimated({
    super.key,
    this.sideBarColor = const Color(0xff1D1D1D),
    this.animatedContainerColor = const Color(0xff323232),
    this.unSelectedTextColor = const Color(0xffA0A5A9),
    this.selectedIconColor = Colors.white,
    this.unselectedIconColor = const Color(0xffA0A5A9),
    this.hoverColor = Colors.black38,
    this.splashColor = Colors.black87,
    this.highlightColor = Colors.black,
    this.borderRadius = 20,
    this.sideBarWidth = 260,
    this.sideBarSmallWidth = 84,
    this.settingsDivider = true,
    this.curve = Curves.easeOut,
    this.sideBarAnimationDuration = const Duration(milliseconds: 700),
    this.floatingAnimationDuration = const Duration(milliseconds: 500),
    this.dividerColor = const Color(0xff929292),
    this.textStyle =
        const TextStyle(fontFamily: "SFPro", fontSize: 16, color: Colors.white),
    required this.mainLogoImage,
    required this.sidebarItems,
    required this.widthSwitch,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<SideBarAnimated> createState() => _SideBarAnimatedState();
}

class _SideBarAnimatedState extends State<SideBarAnimated> {
  late double _width;
  late double _height;
  late double sideBarItemHeight = 48;
  double _itemIndex = 0.0;
  bool _minimize = false;

  @override
  void initState() {
    if (widget.sidebarItems.isEmpty) {
      throw "Side bar Items Can't be empty";
    }
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  ///Animation creator function
  void moveToNewIndex(int index) {

    ///Timer removed to make it one time animation for better performance
    ///here when we reach the index then we stop because we hit the targeted index
    setState(() {
      _itemIndex = index.toDouble();
    });
    widget.onTap?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    _height = MediaQuery.sizeOf(context).height;
    _width = MediaQuery.sizeOf(context).width;
    final isStatusBarAvailable = MediaQuery.of(context).padding.top > 0;
    ///using animated container for the side bar for smooth responsive
    return AnimatedContainer(
      curve: widget.curve,
      height: _height,
      margin: const EdgeInsets.all(20),
      width: _width >= widget.widthSwitch && !_minimize
          ? widget.sideBarWidth
          : widget.sideBarSmallWidth,
      decoration: BoxDecoration(
        color: widget.sideBarColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      duration: widget.sideBarAnimationDuration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
                left: _width >= widget.widthSwitch && !_minimize ? 20 : 18,
                top: 24),
            child: Image.asset(
              widget.mainLogoImage,
              width: 48,
              height: 48,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                  top: isStatusBarAvailable ? 20 : 40,
                  left: _width >= widget.widthSwitch && !_minimize ? 20 : 18,
                  right: _width >= widget.widthSwitch && !_minimize ? 20 : 18,
                  bottom: 24),
              child: Column(
                children: [
                  Builder(
                    builder: (context) {
                      double totalHeight = widget.sidebarItems.length * sideBarItemHeight +
                          (widget.sidebarItems.length - 2) * 8.0 +
                          (widget.settingsDivider ? 12.0 : 8.0);
                      
                      double calculateTop(double index) {
                        if (!widget.settingsDivider) return index * (sideBarItemHeight + 8.0);
                        if (index <= widget.sidebarItems.length - 2) {
                          return index * (sideBarItemHeight + 8.0);
                        } else {
                          double extra = (index - (widget.sidebarItems.length - 2)) * 4.0;
                          return index * (sideBarItemHeight + 8.0) + extra;
                        }
                      }

                      return SizedBox(
                        height: totalHeight,
                        child: Stack(
                          children: [
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemBuilder: (context, index) {
                                return sideBarItem(
                                    textStyle: widget.textStyle,
                                    unselectedIconColor: widget.unselectedIconColor,
                                    unSelectedTextColor: widget.unSelectedTextColor,
                                    widthSwitch: widget.widthSwitch,
                                    minimize: _minimize,
                                    height: sideBarItemHeight,
                                    hoverColor: widget.hoverColor,
                                    splashColor: widget.splashColor,
                                    highlightColor: widget.highlightColor,
                                    width: _width,
                                    icon:
                                        widget.sidebarItems[index].iconUnselected ??
                                            widget.sidebarItems[index].iconSelected,
                                    text: widget.sidebarItems[index].text,
                                    onTap: () => moveToNewIndex(index),
                                    onLongPress: () => widget.onLongPress?.call(index));
                              },
                              separatorBuilder: (context, index) {
                                if (index == widget.sidebarItems.length - 2 &&
                                    widget.settingsDivider) {
                                  return Divider(
                                    height: 12,
                                    thickness: 0.2,
                                    color: widget.dividerColor,
                                  );
                                } else {
                                  return const SizedBox(
                                    height: 8,
                                  );
                                }
                              },
                              itemCount: widget.sidebarItems.length,
                            ),
                            AnimatedPositioned(
                              top: calculateTop(_itemIndex),
                              left: 0,
                              right: 0,
                              duration: widget.floatingAnimationDuration,
                              curve: widget.curve,
                              child: Container(
                                height: sideBarItemHeight,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: widget.animatedContainerColor,
                                    borderRadius: BorderRadius.circular(12)),
                                child: ListView(
                                  shrinkWrap: false,
                                  clipBehavior: Clip.antiAliasWithSaveLayer,
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    Icon(
                                      widget.sidebarItems[_itemIndex.floor()]
                                          .iconSelected,
                                      color: Colors.white,
                                    ),
                                    if (_width >= widget.widthSwitch && !_minimize)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 12.0),
                                        child: Text(
                                          widget.sidebarItems[_itemIndex.floor()]
                                              .text,
                                          overflow: TextOverflow.ellipsis,
                                          style: widget.textStyle,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  ),
                ],
              ),
            ),
          ),
          if (_width >= widget.widthSwitch)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: IconButton(
                  hoverColor: Colors.black38,
                  splashColor: Colors.black87,
                  highlightColor: Colors.black,
                  onPressed: () {
                    setState(() => _minimize = !_minimize);
                  },
                  icon: Icon(
                      _width >= widget.widthSwitch && _minimize
                          ? CupertinoIcons.arrow_right
                          : Icons.space_dashboard_outlined,
                      color: widget.selectedIconColor)),
            )
        ],
      ),
    );
  }
}

/// Sidebar model Widget the we used it inside the ListView with inkwell to make each item clickable

Widget sideBarItem({
  required IconData icon,
  required String text,
  required double width,
  required double widthSwitch,
  required bool minimize,
  required double height,
  required Color hoverColor,
  required Color unselectedIconColor,
  required Color splashColor,
  required Color highlightColor,
  required Color unSelectedTextColor,
  required Function() onTap,
  VoidCallback? onLongPress,
  required TextStyle textStyle,
}) {
  return Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAliasWithSaveLayer,
    child: InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      hoverColor: hoverColor,
      splashColor: splashColor,
      highlightColor: highlightColor,
      child: SizedBox(
        height: height,
        child: ListView(
          padding: const EdgeInsets.all(12),
          shrinkWrap: true,
          clipBehavior: Clip.antiAliasWithSaveLayer,
          scrollDirection: Axis.horizontal,
          children: [
            Icon(
              icon,
              color: unselectedIconColor,
            ),
            if (width >= widthSwitch && !minimize)
              Padding(
                padding: const EdgeInsets.only(left: 12.0),
                child: Text(
                  text,
                  overflow: TextOverflow.clip,
                  style: textStyle.copyWith(color: unSelectedTextColor),
                  textAlign: TextAlign.left,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

///Sidebar model contains two icon data and string for the text main Icon can't be null but unselected icon can be null and in this case it will be the main Icon

/// Sidebar model
class SideBarItem {
  final IconData iconSelected;
  final IconData? iconUnselected;
  final String text;

  SideBarItem({
    required this.iconSelected,
    this.iconUnselected,
    required this.text,
  });
}
