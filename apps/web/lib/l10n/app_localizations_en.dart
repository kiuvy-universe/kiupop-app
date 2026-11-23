// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'KiuPop';

  @override
  String get tagline => 'Your store starts with an idea.';

  @override
  String get welcomeSubtitle =>
      'Kiu understands what you sell, asks a few questions and creates a beautiful store, ready to share and take orders on WhatsApp.';

  @override
  String get welcomeStep1 => 'Sign in with Google or your email in one tap.';

  @override
  String get welcomeStep2 => 'Tell Kiu what you sell, in your own words.';

  @override
  String get welcomeStep3 =>
      'Watch your store inflate… POP! Share it and get orders.';

  @override
  String get createStoreCta => 'Create my store';

  @override
  String get haveStoreCta => 'I already have an account';

  @override
  String get seeDemoStore => 'See a sample store';

  @override
  String get back => 'Back';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get show => 'Show';

  @override
  String get hide => 'Hide';

  @override
  String get createStoreTitle => 'Create your store';

  @override
  String get createStoreIntro =>
      'We only need two things. You can change everything later.';

  @override
  String get storeNameLabel => 'Business name';

  @override
  String get storeNameHint => 'e.g. Western Flowers';

  @override
  String get storeNameError => 'Enter your business name (at least 2 letters).';

  @override
  String get whatsappLabel => 'WhatsApp for orders';

  @override
  String get whatsappHelper =>
      'Costa Rica number (8 digits) or international with +';

  @override
  String get whatsappError => 'Enter a valid WhatsApp number.';

  @override
  String get storeDescriptionLabel => 'Description (optional)';

  @override
  String get storeDescriptionHint => 'What do you sell? Where are you?';

  @override
  String get createStoreSubmit => 'Create my store';

  @override
  String get storeReadyTitle => 'Your store is ready!';

  @override
  String storeReadyBody(String name) {
    return '$name now has its catalog. This is your public link:';
  }

  @override
  String get credentialTitle => 'Save your admin key';

  @override
  String get credentialWarning =>
      'This key lets you edit your store again. Keep it safe: we won\'t show it again and it can\'t be recovered in this version.';

  @override
  String get copyCredential => 'Copy key';

  @override
  String get credentialCopied => 'Key copied. Keep it somewhere safe.';

  @override
  String get credentialSavedCheck => 'I saved my key';

  @override
  String get continueToProducts => 'Continue to my products';

  @override
  String get loginTitle => 'Sign in to my store';

  @override
  String get loginIntro =>
      'Paste the admin key you saved when creating your store.';

  @override
  String get credentialLabel => 'Admin key';

  @override
  String get credentialInvalid =>
      'That key is not valid. Check you copied all of it.';

  @override
  String get loginSubmit => 'Sign in';

  @override
  String get loginRecoveryNote =>
      'Lost your key? It can\'t be recovered in this preview.';

  @override
  String get signOut => 'Sign out';

  @override
  String get tabProducts => 'Products';

  @override
  String get tabMyStore => 'My store';

  @override
  String get addProduct => 'Add product';

  @override
  String get loadProductsError => 'We couldn\'t load your products';

  @override
  String get noProductsTitle => 'Add your first product';

  @override
  String get noProductsBody =>
      'Tap “Add product”. Three products are enough to share your store.';

  @override
  String productsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count products',
      one: '1 product',
    );
    return '$_temp0';
  }

  @override
  String get visibleInStore => 'Visible in your store';

  @override
  String get hiddenFromStore => 'Hidden';

  @override
  String availableToggle(String name) {
    return 'Show $name in the store';
  }

  @override
  String get productShown => 'The product is now visible.';

  @override
  String get productHidden => 'The product is now hidden.';

  @override
  String get newProductTitle => 'New product';

  @override
  String get editProductTitle => 'Edit product';

  @override
  String get productNameLabel => 'Name';

  @override
  String get productNameError => 'Enter the product name.';

  @override
  String get priceLabel => 'Price in colones';

  @override
  String get priceHelper => 'Numbers only, no decimals. e.g. 2000';

  @override
  String get priceError => 'Enter a price greater than zero.';

  @override
  String get productDescriptionLabel => 'Description';

  @override
  String get addPhoto => 'Add photo';

  @override
  String get changePhoto => 'Change photo';

  @override
  String get photoHelper => 'JPG, PNG or WebP, up to 5 MB.';

  @override
  String get saveProduct => 'Save product';

  @override
  String get productSaved => 'Product saved.';

  @override
  String photoUploadFailed(String reason) {
    return 'The product was saved, but the photo wasn\'t: $reason';
  }

  @override
  String get aiIntro =>
      'Describe what you sell in your own words and we\'ll suggest a name and description. You decide what to use.';

  @override
  String get aiDisabled =>
      'KiuPop AI isn\'t available here. You can write the description yourself.';

  @override
  String get aiNoteHint => 'e.g. Natural red rose for gifts';

  @override
  String get improveWithAi => 'Improve with AI';

  @override
  String get aiWorking => 'Thinking…';

  @override
  String get aiNeedsText => 'Write something about your product first.';

  @override
  String get aiProposal => 'KiuPop AI suggestion';

  @override
  String get aiPriceUntouched => 'AI never changes the price: you set it.';

  @override
  String get aiUse => 'Use this suggestion';

  @override
  String get aiDiscard => 'Discard';

  @override
  String get aiAccepted => 'Done. Review and edit the text before saving.';

  @override
  String get yourLink => 'Your public link';

  @override
  String get viewMyStore => 'View my store';

  @override
  String get copyLink => 'Copy link';

  @override
  String get linkCopied => 'Link copied.';

  @override
  String get shareWhatsApp => 'Share on WhatsApp';

  @override
  String shareMessage(String store, String link) {
    return 'Check out $store\'s catalog! Order here: $link';
  }

  @override
  String get catalogPreview => 'How your catalog looks';

  @override
  String get catalogPreviewEmpty => 'No visible products yet.';

  @override
  String get storeNotFound => 'We couldn\'t find this store';

  @override
  String get storeNotFoundBody => 'Check the link you were sent.';

  @override
  String get loadCatalogError => 'We couldn\'t load the catalog';

  @override
  String get catalogEmpty => 'Products coming soon';

  @override
  String get catalogEmptyBody => 'This store has no products available yet.';

  @override
  String get addToCart => 'Add';

  @override
  String decrease(String name) {
    return 'Remove one $name';
  }

  @override
  String increase(String name) {
    return 'Add one $name';
  }

  @override
  String cartItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'View order · $count items',
      one: 'View order · 1 item',
    );
    return '$_temp0';
  }

  @override
  String get yourOrder => 'Your order';

  @override
  String get cartEmpty => 'Your order is empty.';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get total => 'Total';

  @override
  String get orderDisclaimer =>
      'The shop confirms availability and final price on WhatsApp. No payment has been made.';

  @override
  String get orderWhatsApp => 'Order on WhatsApp';

  @override
  String get orderPrepared =>
      'WhatsApp opened with your order ready. Send it so the shop can confirm.';

  @override
  String get whatsappOpenFailed =>
      'We couldn\'t open WhatsApp. Check that pop-ups are allowed.';

  @override
  String get errorOffline =>
      'Can\'t reach KiuPop. Check your connection and try again.';

  @override
  String get errorTimeout => 'KiuPop took too long to respond. Try again.';

  @override
  String get errorGeneric => 'Something went wrong. Try again.';

  @override
  String get kiuLoginTitle => 'Create your store with Kiu';

  @override
  String get loginSubtitle => 'Sign in with one tap and let\'s start talking.';

  @override
  String get loginEmulatorNotice =>
      'Local mode: emulator test accounts. Don\'t use your real password.';

  @override
  String get loginDisabledNotice =>
      'Sign-in is not configured in this environment.';

  @override
  String get loginGoogle => 'Continue with Google';

  @override
  String get loginFacebook => 'Continue with Facebook';

  @override
  String get loginFacebookSoon => 'Facebook (coming soon)';

  @override
  String get loginFacebookPending => 'Enabled once the Meta app is configured.';

  @override
  String get loginOrEmail => 'or with your email';

  @override
  String get loginEmail => 'Email';

  @override
  String get loginPassword => 'Password';

  @override
  String get loginPasswordHelp => 'At least 6 characters.';

  @override
  String get loginCreateAccount => 'Create account';

  @override
  String get loginSignIn => 'Sign in';

  @override
  String get loginHaveAccount => 'I have an account · Sign in';

  @override
  String get loginNoAccount => 'No account yet · Create one';

  @override
  String get loginLegacyKey => 'Sign in with a kp_ key (POC stores)';

  @override
  String get authInvalidCredentials => 'Email or password don\'t match.';

  @override
  String get authEmailInUse =>
      'That email already has an account. Tap “Sign in”.';

  @override
  String get authWeakPassword => 'Use at least 6 characters.';

  @override
  String get authInvalidEmail => 'Enter a valid email.';

  @override
  String get authProviderDisabled => 'This sign-in method is not enabled yet.';

  @override
  String get authNetwork => 'No connection. Check your internet and try again.';

  @override
  String get authUnknown => 'We couldn\'t sign you in. Try again.';

  @override
  String get kiuPopWord => 'POP!';

  @override
  String get kiuSemantic => 'Kiu, the KiuPop assistant';

  @override
  String get kiuThinking => 'Kiu is thinking…';

  @override
  String get kiuLoadError => 'We couldn\'t open your chat with Kiu';

  @override
  String get aiModeClaude => 'AI';

  @override
  String get aiModeLocal => 'Local mode';

  @override
  String get aiModeClaudeHelp => 'Kiu uses an AI model to understand you.';

  @override
  String get aiModeLocalHelp =>
      'No AI connected: Kiu uses local rules and never invents data.';

  @override
  String get stageListening => 'Kiu is listening';

  @override
  String stageBuilding(int percent) {
    return 'Building your store… $percent%';
  }

  @override
  String get stageReady => 'Your store is ready!';

  @override
  String get stagePublished => 'Your store is live';

  @override
  String get skipAnimation => 'Skip animation';

  @override
  String get seePreview => 'See preview';

  @override
  String get taskDone => 'done';

  @override
  String get taskRunning => 'in progress';

  @override
  String get taskNeedsInput => 'needs your answer';

  @override
  String get taskSkipped => 'skipped';

  @override
  String get taskFailed => 'could not complete';

  @override
  String get taskPending => 'pending';

  @override
  String get composerHintFirst =>
      'E.g.: I\'m Bella Flowers, I sell flowers and arrangements…';

  @override
  String get composerHintAnswer => 'Type your answer…';

  @override
  String get skipQuestion => 'Skip this question';

  @override
  String get send => 'Send';

  @override
  String get publishCta => 'Publish my store';

  @override
  String get publishConfirmTitle => 'Publish your store?';

  @override
  String get publishConfirmBody =>
      'Anyone with the link will see it and can order on WhatsApp. Real online payments stay off.';

  @override
  String get publishConfirmCta => 'Yes, publish';

  @override
  String get publishFailed => 'We couldn\'t publish. Try again.';

  @override
  String get previewTitle => 'Preview';

  @override
  String get previewDraft => 'Preview · not public yet';

  @override
  String get previewPublished => 'This is what your customers see';

  @override
  String get previewEmpty =>
      'Tell Kiu about your business and your store will appear here.';

  @override
  String get previewBuilding => 'Kiu is building your store…';

  @override
  String get shareTitle => 'Share your store!';

  @override
  String shareText(String name) {
    return 'Check out $name\'s store';
  }

  @override
  String get share => 'Share';

  @override
  String get openMyStore => 'View my store';

  @override
  String get addPhotosInAdmin => 'Add photos and edit';

  @override
  String get noStoreYet => 'You don\'t have a store yet';

  @override
  String get noStoreYetBody =>
      'Tell Kiu about your business and we\'ll create it in minutes.';

  @override
  String get createWithKiu => 'Create with Kiu';

  @override
  String get cancel => 'Cancel';

  @override
  String get sfCatalog => 'Catalog';

  @override
  String get sfFeatured => 'Featured';

  @override
  String get sfWriteWhatsApp => 'Message on WhatsApp';

  @override
  String get sfAvailableWhenPublished => 'WhatsApp (after publishing)';

  @override
  String get sfDelivery => 'Delivery';

  @override
  String get sfDeliveryHome => 'Home delivery';

  @override
  String get sfDeliveryPickup => 'Pickup available';

  @override
  String get sfDeliveryCoordinate => 'We arrange delivery on WhatsApp.';

  @override
  String sfPaymentsToCoordinate(String methods) {
    return 'Payments to arrange: $methods';
  }

  @override
  String get sfRealPaymentsPending => 'Real online payments: not active yet.';

  @override
  String get sfContact => 'Contact';

  @override
  String get sfMadeWith => 'Made with KiuPop';

  @override
  String get sfDraftBadge => 'Preview · draft';

  @override
  String get sfTestCheckout => 'Pay online (test)';

  @override
  String get checkoutTitle => 'Test payment';

  @override
  String get checkoutTestNotice => 'Test mode: no real money is charged.';

  @override
  String get checkoutSimulateApprove => 'Simulate approved payment';

  @override
  String get checkoutSimulateDecline => 'Simulate decline';

  @override
  String get checkoutApproved => 'Test payment approved';

  @override
  String get checkoutDeclined => 'Test payment declined';

  @override
  String get checkoutNoRealMoney =>
      'No real money was charged. The store confirms your order on WhatsApp.';

  @override
  String get catFlores => 'Flowers';

  @override
  String get catReposteria => 'Bakery';

  @override
  String get catComida => 'Food';

  @override
  String get catRopa => 'Fashion';

  @override
  String get catBelleza => 'Beauty';

  @override
  String get catArtesania => 'Crafts';

  @override
  String get catMascotas => 'Pets';

  @override
  String get catPlantas => 'Plants';

  @override
  String get catTecnologia => 'Tech';

  @override
  String get catOtro => 'Store';

  @override
  String get createAnotherStore => 'Create another store';

  @override
  String get attachFiles =>
      'Share photos or your catalog (Excel, CSV, text or PDF)';

  @override
  String fileTooMany(String name) {
    return '$name: you already shared the maximum number of files.';
  }

  @override
  String fileTooBig(String name) {
    return '$name: is too large (20 MB max).';
  }

  @override
  String uploadingFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return 'Uploading $_temp0…';
  }

  @override
  String get fileReceived => 'received';

  @override
  String get fileProcessing => 'processing';

  @override
  String get fileProcessed => 'done';

  @override
  String get fileNeedsReview => 'review';

  @override
  String get fileError => 'error';

  @override
  String get googleTestTitle => 'Test Google account';

  @override
  String get googleTestBody =>
      'Local mode: the emulator creates a test account. No real Google account is used.';

  @override
  String get googleTestName => 'Name';

  @override
  String get micStart => 'Dictate (your browser transcribes; we keep no audio)';

  @override
  String get micStop => 'Stop dictation';

  @override
  String get micDenied =>
      'Allow microphone access to dictate. You can also type.';

  @override
  String get micError => 'I couldn\'t hear you. Try again or type.';

  @override
  String get uploadCatalog => 'Upload catalog (Excel, CSV or text)';

  @override
  String get themeSystem => 'Theme: automatic (follows your device)';

  @override
  String get themeLight => 'Theme: light';

  @override
  String get themeDark => 'Theme: dark';

  @override
  String get kiuSaid => 'Kiu said';

  @override
  String get youSaid => 'You said';

  @override
  String get scrollToLatest => 'Go to latest message';

  @override
  String get welcomeLead =>
      'Tell Kiu about it and watch it become a store ready to share.';

  @override
  String get loginHowItWorks => 'How it works';

  @override
  String get loginJustLooking => 'Just looking? See an example store';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get themeShortSystem => 'Auto';

  @override
  String get themeShortLight => 'Light';

  @override
  String get themeShortDark => 'Dark';

  @override
  String get themeLabel => 'Appearance';

  @override
  String get kiuBrainLabel => 'How Kiu thinks';

  @override
  String get stageListeningHint =>
      'Tell me what you sell and your business name.';

  @override
  String get stageBuildingHint =>
      'Kiu is building your catalog from what you told me.';

  @override
  String get stageReadyHint =>
      'Take a look before publishing. You decide when.';

  @override
  String get stagePublishedHint => 'You can share it and take orders now.';

  @override
  String get kiuDiagnosis => 'Kiu\'s diagnosis';

  @override
  String get paywallTestBadge => 'Demo mode';

  @override
  String get paywallTitle => 'Your store is ready for the next step.';

  @override
  String get paywallLead =>
      'You already have the design, the catalog and your products organized. Activate KiuPop to share your store and start receiving sales opportunities.';

  @override
  String get paywallPerMonth => ' / month';

  @override
  String get paywallPerStore =>
      'per active store. Pause it and you don\'t pay.';

  @override
  String get paywallIncludesLink => 'Public link to share on social media';

  @override
  String get paywallIncludesWhatsApp => 'Orders straight to your WhatsApp';

  @override
  String get paywallIncludesQr => 'Catalog with link and QR code';

  @override
  String get paywallTestCard => 'Test card •••• 4242';

  @override
  String get paywallFreeNote =>
      'Seeing and adjusting your store with Kiu is free.';

  @override
  String paywallPayCta(String price) {
    return 'Pay $price and publish';
  }

  @override
  String get paywallPaying => 'Simulating activation…';

  @override
  String get paywallLater => 'Not now';

  @override
  String get paywallFailed => 'We couldn\'t activate your plan. Try again.';

  @override
  String get paywallActivated =>
      'Test activation done: nothing was charged. Publishing your store…';

  @override
  String get voiceTitle => 'Talk to Kiu';

  @override
  String voiceIdleHint(int seconds) {
    return 'Tell me what you sell, your business name and your prices. Up to $seconds seconds.';
  }

  @override
  String get voiceTapToRecord => 'Tap to record';

  @override
  String get voiceStart => 'Start recording';

  @override
  String get voiceStop => 'Stop recording';

  @override
  String get voiceRecording => 'Recording…';

  @override
  String get voiceDiscard => 'Discard';

  @override
  String get voicePlay => 'Listen';

  @override
  String get voicePause => 'Pause';

  @override
  String get voiceRerecord => 'Record again';

  @override
  String get voiceDelete => 'Delete';

  @override
  String get voiceTranscribe => 'Transcribe';

  @override
  String get voiceTranscribing => 'Kiu is listening to your audio…';

  @override
  String get voiceReviewTitle => 'This is what I understood';

  @override
  String get voiceReviewHint =>
      'Fix names, prices or quantities if needed. Kiu only receives this text.';

  @override
  String get voiceTranscriptLabel => 'Your idea, as text';

  @override
  String get voiceSend => 'Send to Kiu';

  @override
  String get voiceWriteInstead => 'I\'d rather type';

  @override
  String get voicePermissionDenied =>
      'I need microphone permission. Enable it in your browser or phone settings, or type to me.';

  @override
  String get voiceMicError =>
      'I couldn\'t use the microphone. Try again or type to me.';

  @override
  String get voiceTooShort => 'The audio is too short. Tell me a bit more.';

  @override
  String get voiceEmptyTranscript => 'Write or fix the text before sending it.';

  @override
  String voiceProvider(String provider) {
    return 'Transcribed with $provider. Audio is not stored.';
  }

  @override
  String get voiceUnavailable =>
      'Voice transcription is not available right now. You can type to Kiu.';

  @override
  String get intakeTitle => 'How do you want to tell Kiu your idea?';

  @override
  String get intakeFree =>
      'Tell me what you imagine. Your first proposal is free.';

  @override
  String get intakeVoiceTitle => 'Talk to Kiu';

  @override
  String get intakeVoiceBody =>
      'Record an audio telling me what you sell. I\'ll take care of the rest.';

  @override
  String get intakeTextTitle => 'Write my idea';

  @override
  String get intakeTextBody => 'Write a description of your business.';

  @override
  String get intakeVoiceOff => 'Audio not available right now';

  @override
  String get revealTitle => 'POP! Your store has taken shape.';

  @override
  String get revealBody =>
      'Kiu organized your business and prepared a store designed for you.';

  @override
  String get revealExplore => 'Explore my store';

  @override
  String get revealAdjust => 'Make an adjustment';

  @override
  String get revealContinue => 'Continue';

  @override
  String get adjustHint =>
      'Tell Kiu what you want to change: colors, names, prices…';

  @override
  String uploadSending(String name) {
    return 'Uploading $name…';
  }

  @override
  String uploadCancel(String name) {
    return 'Cancel upload of $name';
  }

  @override
  String get uploadRetry => 'Retry';

  @override
  String get uploadRemove => 'Remove';

  @override
  String uploadCancelled(String name) {
    return '$name: upload cancelled.';
  }

  @override
  String fileTooManyTotal(String name, int mb) {
    return '$name: with this file you exceed $mb MB per store.';
  }

  @override
  String get voiceNote => 'Voice note';

  @override
  String get paywallDemoNotice =>
      'Demo mode. KiuPop does not process subscriptions or real charges yet. This activation is simulated and no amount will be charged.';

  @override
  String get paywallPlanName => 'Demo plan';

  @override
  String get paywallPriceNote => 'Reference price for the demo. Not charged.';

  @override
  String get paywallIncludedTitle => 'Included today';

  @override
  String get paywallBenefitCatalog => 'Public catalog';

  @override
  String get paywallBenefitLinks => 'Shareable links';

  @override
  String get paywallBenefitCart => 'Cart';

  @override
  String get paywallBenefitWhatsApp => 'Orders via WhatsApp';

  @override
  String get paywallBenefitAdmin => 'Product management';

  @override
  String get paywallBenefitDesign => 'Visual customization';

  @override
  String get paywallBenefitKiu => 'Help from Kiu';

  @override
  String get paywallSoonTitle => 'Coming soon';

  @override
  String get paywallSoonPayments => 'Real online payments';

  @override
  String get paywallSoonIntegrations => 'Advanced integrations';

  @override
  String get paywallSimulateCta => 'Simulate activation';
}
