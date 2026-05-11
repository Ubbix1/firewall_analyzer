import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _launchUrl() async {
    final Uri url = Uri.parse('https://github.com/Ubbix1');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About', style: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 1.2)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Simple Logo ───────────────────────────────────────────────
              Icon(
                Icons.shield_outlined,
                size: 80,
                color: colorScheme.primary.withOpacity(0.8),
              ),
              const SizedBox(height: 24),
              Text(
                'FIREWALL ANALYZER',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w300,
                  letterSpacing: 4.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'VERSION 3.6.0',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                  letterSpacing: 2.0,
                ),
              ),
              
              const SizedBox(height: 64),
              
              // ── Minimalist Info Section ──────────────────────────────────
              Text(
                'A minimalist ecosystem for network security monitoring. Designed for clarity, performance, and real-time insights.',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  color: colorScheme.onSurface.withOpacity(0.8),
                  fontWeight: FontWeight.w300,
                ),
              ),
              
              const SizedBox(height: 48),
              
              // ── List of features ──────────────────────────────────────────
              _buildMinimalFeature('Real-time packet inspection'),
              _buildMinimalFeature('Backend threat intelligence'),
              _buildMinimalFeature('Unified security dashboard'),
              _buildMinimalFeature('Low resource footprint'),
              
              const SizedBox(height: 80),
              
              // ── Minimal Footer ────────────────────────────────────────────
              Text(
                'CRAFTED BY',
                style: textTheme.labelSmall?.copyWith(
                  letterSpacing: 3,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Owais',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 24),
              InkWell(
                onTap: _launchUrl,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'github.com/Ubbix1',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalFeature(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w400,
          color: Colors.grey,
        ),
      ),
    );
  }
}

