import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/graphql/graphql_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/repository/account_repository.dart';
import '../../data/utils/review_attachment_encoder.dart';
import '../bloc/add_review_bloc.dart';
import '../widgets/review_video_thumbnail.dart';
import 'review_video_player_page.dart';

/// Add Review Page — Figma node-id=2157-6741
///
/// Full-screen page for submitting a product review:
///   - AppBar: "Add Review" title (left) + × close button (right)
///   - Product card: image + name on neutral-100 background
///   - Star rating selector (1–5, orange #FE9A00 filled stars)
///   - Nick Name* text field
///   - Summary text field
///   - Review multi-line text field
///   - Photos & Videos picker (up to 5 files, 5 MB each)
///   - "Submit Review" orange button (full width)
///
/// Requires [productId], [productName], and optional [productImageUrl]
/// to display the product card and submit the review.
class AddReviewPage extends StatefulWidget {
  /// Numeric product ID for the API mutation
  final int productId;

  /// Product name shown in the card header
  final String productName;

  /// Product image URL (nullable)
  final String? productImageUrl;

  /// Pre-selected attachments. Test seam; production callers omit it.
  @visibleForTesting
  final List<File> initialAttachments;

  const AddReviewPage({
    super.key,
    required this.productId,
    required this.productName,
    this.productImageUrl,
    this.initialAttachments = const [],
  });

  /// Navigate to AddReviewPage from any context.
  /// Creates its own [AccountRepository] from the auth token so it works
  /// from product-detail, wishlist, or any other page — not just account.
  /// Returns `true` if a review was successfully submitted.
  static Future<bool?> navigate(
    BuildContext context, {
    required int productId,
    required String productName,
    String? productImageUrl,
  }) {
    // Try to reuse an existing AccountRepository from the widget tree;
    // if not available, create one from the current auth token.
    AccountRepository repository;
    try {
      repository = context.read<AccountRepository>();
    } catch (_) {
      final authState = context.read<AuthBloc>().state;
      final client = authState is AuthAuthenticated
          ? GraphQLClientProvider.authenticatedClient(authState.token).value
          : GraphQLClientProvider.client.value;
      repository = AccountRepository(client: client);
    }

    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RepositoryProvider.value(
          value: repository,
          child: BlocProvider(
            create: (_) => AddReviewBloc(repository: repository),
            child: AddReviewPage(
              productId: productId,
              productName: productName,
              productImageUrl: productImageUrl,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<AddReviewPage> createState() => _AddReviewPageState();
}

class _AddReviewPageState extends State<AddReviewPage> {
  final _formKey = GlobalKey<FormState>();
  final _nickNameController = TextEditingController();
  final _summaryController = TextEditingController();
  final _reviewController = TextEditingController();
  int _selectedRating = 0;
  String? _ratingErrorText;
  final ImagePicker _imagePicker = ImagePicker();
  late final List<File> _attachments = List.of(widget.initialAttachments);

  @override
  void dispose() {
    _nickNameController.dispose();
    _summaryController.dispose();
    _reviewController.dispose();
    super.dispose();
  }

  void _onSubmit() {
    final l10n = AppLocalizations.of(context)!;

    final isFormValid = _formKey.currentState!.validate();
    final ratingError =
        _selectedRating == 0 ? l10n.accountPleaseSelectRating : null;

    setState(() {
      _ratingErrorText = ratingError;
    });

    if (!isFormValid || ratingError != null) {
      return;
    }

    context.read<AddReviewBloc>().add(SubmitReview(
          productId: widget.productId,
          title: _summaryController.text.trim(),
          comment: _reviewController.text.trim(),
          rating: _selectedRating,
          name: _isLoggedIn ? "" : _nickNameController.text.trim(),
          attachments: List.unmodifiable(_attachments),
        ));
  }

  bool get _isLoggedIn {
    final authState = context.read<AuthBloc>().state;
    return authState is AuthAuthenticated;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: isDark ? AppColors.neutral900 : AppColors.white,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.neutral900 : AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Text(
          l10n.accountAddReview,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: isDark ? AppColors.neutral200 : AppColors.black,
          ),
        ),
        actions: [
          // × close button — Figma: right side of AppBar
          IconButton(
            icon: Icon(
              Icons.close,
              size: 24,
              color: isDark ? AppColors.neutral200 : AppColors.neutral900,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: BlocConsumer<AddReviewBloc, AddReviewState>(
        listener: (context, state) {
          if (state.status == AddReviewStatus.success) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(state.successMessage ?? l10n.accountReviewSubmitted),
                  backgroundColor: AppColors.successGreen,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            // Pop back with true to signal a review was created
            Navigator.of(context).pop(true);
          }
          if (state.status == AddReviewStatus.error &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage!),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
            context
                .read<AddReviewBloc>()
                .add(const ClearAddReviewMessage());
          }
        },
        builder: (context, state) {
          final isSubmitting =
              state.status == AddReviewStatus.submitting;

          // A tap (not a scroll) anywhere outside a field closes the keyboard.
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Scrollable form content
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),

                            // ── Product Card ──
                            _buildProductCard(context),

                            const SizedBox(height: 20),

                            // ── Rating Section ──
                            _buildRatingSection(context),

                            const SizedBox(height: 20),

                            // ── Nick Name Field ──
                            if (!_isLoggedIn) ...[
                              _buildTextField(
                                context,
                                label: l10n.accountNickName,
                                isRequired: true,
                                controller: _nickNameController,
                                hintText: l10n.accountEnterYourName,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return l10n.accountNameRequired;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                            ],

                            // ── Summary Field ──
                            _buildTextField(
                              context,
                              label: l10n.accountSummary,
                              isRequired: true,
                              controller: _summaryController,
                              hintText: l10n.accountReviewSummaryHint,
                              maxLines: 3,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return l10n.accountSummaryRequired;
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 20),

                            // ── Review Field ──
                            _buildTextField(
                              context,
                              label: l10n.accountReview,
                              isRequired: true,
                              controller: _reviewController,
                              hintText: l10n.accountDetailedReviewHint,
                              maxLines: 5,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return l10n.accountReviewRequired;
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 20),

                            // ── Photos & Videos ──
                            _buildMediaSection(context, isSubmitting),

                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),

                    // ── Submit Button (pinned at bottom) ──
                    _buildSubmitButton(context, isSubmitting),
                  ],
                ),
            ),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Product Card — Figma: rounded-10, bg #F5F5F5
  // ──────────────────────────────────────────────

  Widget _buildProductCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.neutral800 : AppColors.neutral100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Product image — 62×62, rounded-8
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isDark ? AppColors.neutral700 : const Color(0x1A0E1019),
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.productImageUrl != null &&
                    widget.productImageUrl!.isNotEmpty
                ? Image.network(
                    widget.productImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        size: 28,
                        color: AppColors.neutral400,
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: 28,
                      color: AppColors.neutral400,
                    ),
                  ),
          ),

          const SizedBox(width: 10),

          // Product name — Figma: Medium 16px, #171717
          Expanded(
            child: Text(
              widget.productName,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: 16,
                color: isDark ? AppColors.neutral200 : AppColors.neutral900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Rating Section — "Rating" label + 5 stars
  // ──────────────────────────────────────────────

  Widget _buildRatingSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Rating" label
        _buildFieldLabel(
          context,
          label: l10n.accountRating,
          isRequired: true,
        ),
        const SizedBox(height: 8),

        // 5 interactive stars
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final starIndex = index + 1;
            final isFilled = starIndex <= _selectedRating;

            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedRating = starIndex;
                  _ratingErrorText = null;
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 36,
                  color: isFilled
                      ? const Color(0xFFFE9A00) // status-info/500
                      : (isDark
                          ? AppColors.neutral600
                          : AppColors.neutral300),
                ),
              ),
            );
          }),
        ),
        if (_ratingErrorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _ratingErrorText!,
            style: TextStyle(
              fontSize: 12,
              color: Colors.red.shade400,
            ),
          ),
        ],
      ],
    );
  }

  // ──────────────────────────────────────────────
  // Text Field — outlined input matching Figma
  // ──────────────────────────────────────────────

  Widget _buildTextField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? hintText,
    bool isRequired = false,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(
          context,
          label: label,
          isRequired: isRequired,
        ),
        const SizedBox(height: 8),

        // Text input — Figma: rounded-10, border #E5E5E5
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w400,
            fontSize: 14,
            color: isDark ? AppColors.neutral200 : AppColors.neutral900,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: AppColors.neutral400,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            filled: false,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? AppColors.neutral700 : AppColors.neutral200,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: AppColors.primary500,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.red.shade400,
                width: 1,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.red.shade400,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(
    BuildContext context, {
    required String label,
    bool isRequired = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RichText(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: isDark ? AppColors.neutral300 : AppColors.neutral900,
        ),
        children: isRequired
            ? [
                TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ]
            : null,
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Photos & Videos — pick, preview, remove
  // ──────────────────────────────────────────────

  Future<void> _showMediaSourceSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? AppColors.neutral800 : AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final textStyle = TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w400,
          fontSize: 16,
          color: isDark ? AppColors.neutral200 : AppColors.neutral900,
        );
        final iconColor = isDark ? AppColors.neutral200 : AppColors.neutral900;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: iconColor),
                title: Text(l10n.accountReviewGallery, style: textStyle),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: Icon(Icons.photo_camera_outlined, color: iconColor),
                title: Text(l10n.accountReviewCamera, style: textStyle),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source != null) await _pickMedia(source);
  }

  Future<void> _pickMedia(ImageSource source) async {
    final l10n = AppLocalizations.of(context)!;
    final remaining = ReviewAttachmentEncoder.maxFiles - _attachments.length;
    if (remaining <= 0) {
      _showMediaMessage(
        l10n.accountReviewMaxFiles(ReviewAttachmentEncoder.maxFiles),
      );
      return;
    }

    List<XFile> picked;
    try {
      if (source == ImageSource.camera) {
        final photo = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        picked = photo == null ? const [] : [photo];
      } else {
        // image_picker throws when limit < 2; null means no limit.
        picked = await _imagePicker.pickMultipleMedia(
          imageQuality: 85,
          limit: remaining > 1 ? remaining : null,
        );
      }
    } catch (e) {
      debugPrint('❌ AddReviewPage._pickMedia error: $e');
      if (mounted) _showMediaMessage(l10n.accountReviewPickFailed);
      return;
    }
    if (picked.isEmpty || !mounted) return;

    final accepted = <File>[];
    final messages = <String>{};
    for (final xFile in picked) {
      if (ReviewAttachmentEncoder.mimeTypeFor(xFile.path) == null) {
        messages.add(l10n.accountReviewUnsupportedFile);
        continue;
      }
      if (await xFile.length() > ReviewAttachmentEncoder.maxFileBytes) {
        messages.add(l10n.accountReviewFileTooLarge);
        continue;
      }
      if (_attachments.length + accepted.length >=
          ReviewAttachmentEncoder.maxFiles) {
        messages.add(
          l10n.accountReviewMaxFiles(ReviewAttachmentEncoder.maxFiles),
        );
        break;
      }
      accepted.add(File(xFile.path));
    }

    if (!mounted) return;
    if (accepted.isNotEmpty) {
      setState(() => _attachments.addAll(accepted));
    }
    if (messages.isNotEmpty) _showMediaMessage(messages.join('\n'));
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  void _showMediaMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Widget _buildMediaSection(BuildContext context, bool isSubmitting) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final canAdd = _attachments.length < ReviewAttachmentEncoder.maxFiles;
    final borderColor = isDark ? AppColors.neutral700 : AppColors.neutral200;
    final addColor = isDark ? AppColors.neutral300 : AppColors.neutral700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(context, label: l10n.accountReviewPhotosVideos),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 8, right: 8),
            itemCount: _attachments.length + (canAdd ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index == _attachments.length) {
                return GestureDetector(
                  key: const ValueKey('add_review_media_add'),
                  onTap: isSubmitting ? null : _showMediaSourceSheet,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          size: 24,
                          color: addColor,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.accountReviewAddMedia,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w400,
                            fontSize: 12,
                            color: addColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return _buildMediaTile(
                index: index,
                file: _attachments[index],
                borderColor: borderColor,
                isSubmitting: isSubmitting,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMediaTile({
    required int index,
    required File file,
    required Color borderColor,
    required bool isSubmitting,
  }) {
    final isVideo = ReviewAttachmentEncoder.isVideoPath(file.path);

    return SizedBox(
      key: ValueKey('add_review_media_tile_$index'),
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
              color: AppColors.neutral800,
            ),
            clipBehavior: Clip.antiAlias,
            child: isVideo
                ? GestureDetector(
                    key: ValueKey('add_review_media_open_$index'),
                    onTap: isSubmitting
                        ? null
                        : () => ReviewVideoPlayerPage.navigateFile(
                              context,
                              file,
                            ),
                    child: ReviewVideoThumbnail(file: file, iconSize: 32),
                  )
                : Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 24,
                        color: AppColors.neutral400,
                      ),
                    ),
                  ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              key: ValueKey('add_review_media_remove_$index'),
              onTap: isSubmitting ? null : () => _removeAttachment(index),
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: AppColors.neutral900,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Submit Button — Figma: orange pill, full width
  // ──────────────────────────────────────────────

  Widget _buildSubmitButton(BuildContext context, bool isSubmitting) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: isSubmitting ? null : _onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary500,
            foregroundColor: AppColors.white,
            disabledBackgroundColor: AppColors.primary500.withValues(alpha: 0.6),
            disabledForegroundColor: AppColors.white.withValues(alpha: 0.8),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(54),
            ),
          ),
          child: isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : Text(
                  l10n.accountSubmitReview,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
