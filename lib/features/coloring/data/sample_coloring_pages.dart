import 'package:flutter/material.dart';

import '../models/coloring_page.dart';

const Color _catDefault = Color(0x00000000);

const ColoringPage sampleHappyCatPage = ColoringPage(
  id: 'happy-cat',
  title: 'Happy Cat',
  category: 'Animals',
  assetPath: 'assets/coloring_pages/happy_cat.svg',
  regions: [
    ColoringRegion(id: 'cat-body', name: 'Body', defaultColor: _catDefault),
    ColoringRegion(id: 'cat-head', name: 'Head', defaultColor: _catDefault),
    ColoringRegion(id: 'cat-ear-left', name: 'Left Ear', defaultColor: _catDefault),
    ColoringRegion(id: 'cat-ear-right', name: 'Right Ear', defaultColor: _catDefault),
    ColoringRegion(id: 'cat-eye-left', name: 'Left Eye', defaultColor: _catDefault),
    ColoringRegion(id: 'cat-eye-right', name: 'Right Eye', defaultColor: _catDefault),
    ColoringRegion(id: 'cat-nose', name: 'Nose', defaultColor: _catDefault),
    ColoringRegion(id: 'cat-collar', name: 'Collar', defaultColor: _catDefault),
    ColoringRegion(id: 'cat-tail', name: 'Tail', defaultColor: _catDefault),
  ],
);

const List<ColoringPage> sampleColoringPages = [sampleHappyCatPage];
