import 'package:flutter/material.dart';

import '../models/coloring_page.dart';

const Color _defaultTransparent = Color(0x00000000);

const ColoringPage sampleHappyCatPage = ColoringPage(
  id: 'happy-cat',
  title: 'Happy Cat',
  categoryId: 'animals',
  assetPath: 'assets/coloring_pages/animals/happy_cat.svg',
  sortOrder: 0,
  regions: [
    ColoringRegion(id: 'cat-body', name: 'Body', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'cat-head', name: 'Head', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'cat-ear-left', name: 'Left Ear', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'cat-ear-right', name: 'Right Ear', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'cat-eye-left', name: 'Left Eye', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'cat-eye-right', name: 'Right Eye', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'cat-nose', name: 'Nose', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'cat-mouth', name: 'Mouth', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'cat-collar', name: 'Collar', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'cat-tail', name: 'Tail', defaultColor: _defaultTransparent),
  ],
);

const ColoringPage samplePlayfulPuppyPage = ColoringPage(
  id: 'playful-puppy',
  title: 'Playful Puppy',
  categoryId: 'animals',
  assetPath: 'assets/coloring_pages/animals/playful_puppy.svg',
  sortOrder: 1,
  regions: [
    ColoringRegion(id: 'puppy-body', name: 'Body', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'puppy-head', name: 'Head', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'puppy-ear-left', name: 'Left Ear', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'puppy-ear-right', name: 'Right Ear', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'puppy-eye-left', name: 'Left Eye', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'puppy-eye-right', name: 'Right Eye', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'puppy-nose', name: 'Nose', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'puppy-mouth', name: 'Mouth', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'puppy-collar', name: 'Collar', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'puppy-tail', name: 'Tail', defaultColor: _defaultTransparent),
  ],
);

const ColoringPage sampleFriendlyLionPage = ColoringPage(
  id: 'friendly-lion',
  title: 'Friendly Lion',
  categoryId: 'animals',
  assetPath: 'assets/coloring_pages/animals/friendly_lion.svg',
  sortOrder: 2,
  regions: [
    ColoringRegion(id: 'lion-mane', name: 'Mane', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'lion-head', name: 'Head', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'lion-body', name: 'Body', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'lion-ear-left', name: 'Left Ear', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'lion-ear-right', name: 'Right Ear', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'lion-eye-left', name: 'Left Eye', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'lion-eye-right', name: 'Right Eye', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'lion-nose', name: 'Nose', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'lion-mouth', name: 'Mouth', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'lion-tail', name: 'Tail', defaultColor: _defaultTransparent),
  ],
);

const ColoringPage sampleCuteElephantPage = ColoringPage(
  id: 'cute-elephant',
  title: 'Cute Elephant',
  categoryId: 'animals',
  assetPath: 'assets/coloring_pages/animals/cute_elephant.svg',
  sortOrder: 3,
  regions: [
    ColoringRegion(id: 'elephant-body', name: 'Body', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'elephant-head', name: 'Head', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'elephant-ear-left', name: 'Left Ear', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'elephant-ear-right', name: 'Right Ear', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'elephant-trunk', name: 'Trunk', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'elephant-eye-left', name: 'Left Eye', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'elephant-eye-right', name: 'Right Eye', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'elephant-cheek', name: 'Cheek', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'elephant-leg-front', name: 'Front Leg', defaultColor: _defaultTransparent),
    ColoringRegion(id: 'elephant-leg-back', name: 'Back Leg', defaultColor: _defaultTransparent),
  ],
);

const List<ColoringPage> sampleColoringPages = [
  sampleHappyCatPage,
  samplePlayfulPuppyPage,
  sampleFriendlyLionPage,
  sampleCuteElephantPage,
];
