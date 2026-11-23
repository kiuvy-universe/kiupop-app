import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In es, this message translates to:
  /// **'KiuPop'**
  String get appTitle;

  /// No description provided for @tagline.
  ///
  /// In es, this message translates to:
  /// **'Tu tienda empieza con una idea.'**
  String get tagline;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Kiu entiende lo que vendés, te hace unas pocas preguntas y crea una tienda preciosa, lista para compartir y recibir pedidos por WhatsApp.'**
  String get welcomeSubtitle;

  /// No description provided for @welcomeStep1.
  ///
  /// In es, this message translates to:
  /// **'Entrá con Google o tu correo en un clic.'**
  String get welcomeStep1;

  /// No description provided for @welcomeStep2.
  ///
  /// In es, this message translates to:
  /// **'Contale a Kiu qué vendés, con tus palabras.'**
  String get welcomeStep2;

  /// No description provided for @welcomeStep3.
  ///
  /// In es, this message translates to:
  /// **'Mirá tu tienda inflarse… ¡POP! Compartila y recibí pedidos.'**
  String get welcomeStep3;

  /// No description provided for @createStoreCta.
  ///
  /// In es, this message translates to:
  /// **'Crear mi tienda'**
  String get createStoreCta;

  /// No description provided for @haveStoreCta.
  ///
  /// In es, this message translates to:
  /// **'Ya tengo cuenta'**
  String get haveStoreCta;

  /// No description provided for @seeDemoStore.
  ///
  /// In es, this message translates to:
  /// **'Ver una tienda de ejemplo'**
  String get seeDemoStore;

  /// No description provided for @back.
  ///
  /// In es, this message translates to:
  /// **'Volver'**
  String get back;

  /// No description provided for @close.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get retry;

  /// No description provided for @show.
  ///
  /// In es, this message translates to:
  /// **'Mostrar'**
  String get show;

  /// No description provided for @hide.
  ///
  /// In es, this message translates to:
  /// **'Ocultar'**
  String get hide;

  /// No description provided for @createStoreTitle.
  ///
  /// In es, this message translates to:
  /// **'Crea tu tienda'**
  String get createStoreTitle;

  /// No description provided for @createStoreIntro.
  ///
  /// In es, this message translates to:
  /// **'Solo necesitamos dos datos. Podrás cambiar todo después.'**
  String get createStoreIntro;

  /// No description provided for @storeNameLabel.
  ///
  /// In es, this message translates to:
  /// **'Nombre del negocio'**
  String get storeNameLabel;

  /// No description provided for @storeNameHint.
  ///
  /// In es, this message translates to:
  /// **'Ej.: Flores de Occidente'**
  String get storeNameHint;

  /// No description provided for @storeNameError.
  ///
  /// In es, this message translates to:
  /// **'Escribe el nombre de tu negocio (mínimo 2 letras).'**
  String get storeNameError;

  /// No description provided for @whatsappLabel.
  ///
  /// In es, this message translates to:
  /// **'WhatsApp para recibir pedidos'**
  String get whatsappLabel;

  /// No description provided for @whatsappHelper.
  ///
  /// In es, this message translates to:
  /// **'Número de Costa Rica (8 dígitos) o internacional con +'**
  String get whatsappHelper;

  /// No description provided for @whatsappError.
  ///
  /// In es, this message translates to:
  /// **'Escribe un número de WhatsApp válido.'**
  String get whatsappError;

  /// No description provided for @storeDescriptionLabel.
  ///
  /// In es, this message translates to:
  /// **'Descripción (opcional)'**
  String get storeDescriptionLabel;

  /// No description provided for @storeDescriptionHint.
  ///
  /// In es, this message translates to:
  /// **'¿Qué vendes? ¿Dónde estás?'**
  String get storeDescriptionHint;

  /// No description provided for @createStoreSubmit.
  ///
  /// In es, this message translates to:
  /// **'Crear mi tienda'**
  String get createStoreSubmit;

  /// No description provided for @storeReadyTitle.
  ///
  /// In es, this message translates to:
  /// **'¡Tu tienda está lista!'**
  String get storeReadyTitle;

  /// No description provided for @storeReadyBody.
  ///
  /// In es, this message translates to:
  /// **'{name} ya tiene su catálogo. Este es tu enlace público:'**
  String storeReadyBody(String name);

  /// No description provided for @credentialTitle.
  ///
  /// In es, this message translates to:
  /// **'Guarda tu clave de administrador'**
  String get credentialTitle;

  /// No description provided for @credentialWarning.
  ///
  /// In es, this message translates to:
  /// **'Con esta clave vuelves a editar tu tienda. Guárdala en un lugar seguro: no la mostraremos de nuevo y en esta versión no se puede recuperar.'**
  String get credentialWarning;

  /// No description provided for @copyCredential.
  ///
  /// In es, this message translates to:
  /// **'Copiar clave'**
  String get copyCredential;

  /// No description provided for @credentialCopied.
  ///
  /// In es, this message translates to:
  /// **'Clave copiada. Guárdala en un lugar seguro.'**
  String get credentialCopied;

  /// No description provided for @credentialSavedCheck.
  ///
  /// In es, this message translates to:
  /// **'Ya guardé mi clave'**
  String get credentialSavedCheck;

  /// No description provided for @continueToProducts.
  ///
  /// In es, this message translates to:
  /// **'Continuar a mis productos'**
  String get continueToProducts;

  /// No description provided for @loginTitle.
  ///
  /// In es, this message translates to:
  /// **'Entrar a mi tienda'**
  String get loginTitle;

  /// No description provided for @loginIntro.
  ///
  /// In es, this message translates to:
  /// **'Pega la clave de administrador que guardaste al crear tu tienda.'**
  String get loginIntro;

  /// No description provided for @credentialLabel.
  ///
  /// In es, this message translates to:
  /// **'Clave de administrador'**
  String get credentialLabel;

  /// No description provided for @credentialInvalid.
  ///
  /// In es, this message translates to:
  /// **'La clave no es válida. Revisa que la copiaste completa.'**
  String get credentialInvalid;

  /// No description provided for @loginSubmit.
  ///
  /// In es, this message translates to:
  /// **'Entrar'**
  String get loginSubmit;

  /// No description provided for @loginRecoveryNote.
  ///
  /// In es, this message translates to:
  /// **'¿Perdiste tu clave? En esta versión de prueba no se puede recuperar.'**
  String get loginRecoveryNote;

  /// No description provided for @signOut.
  ///
  /// In es, this message translates to:
  /// **'Salir'**
  String get signOut;

  /// No description provided for @tabProducts.
  ///
  /// In es, this message translates to:
  /// **'Productos'**
  String get tabProducts;

  /// No description provided for @tabMyStore.
  ///
  /// In es, this message translates to:
  /// **'Mi tienda'**
  String get tabMyStore;

  /// No description provided for @addProduct.
  ///
  /// In es, this message translates to:
  /// **'Agregar producto'**
  String get addProduct;

  /// No description provided for @loadProductsError.
  ///
  /// In es, this message translates to:
  /// **'No pudimos cargar tus productos'**
  String get loadProductsError;

  /// No description provided for @noProductsTitle.
  ///
  /// In es, this message translates to:
  /// **'Agrega tu primer producto'**
  String get noProductsTitle;

  /// No description provided for @noProductsBody.
  ///
  /// In es, this message translates to:
  /// **'Toca «Agregar producto». Con tres productos ya puedes compartir tu tienda.'**
  String get noProductsBody;

  /// No description provided for @productsCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 producto} other{{count} productos}}'**
  String productsCount(int count);

  /// No description provided for @visibleInStore.
  ///
  /// In es, this message translates to:
  /// **'Visible en tu tienda'**
  String get visibleInStore;

  /// No description provided for @hiddenFromStore.
  ///
  /// In es, this message translates to:
  /// **'Oculto'**
  String get hiddenFromStore;

  /// No description provided for @availableToggle.
  ///
  /// In es, this message translates to:
  /// **'Mostrar {name} en la tienda'**
  String availableToggle(String name);

  /// No description provided for @productShown.
  ///
  /// In es, this message translates to:
  /// **'El producto ahora se ve en tu tienda.'**
  String get productShown;

  /// No description provided for @productHidden.
  ///
  /// In es, this message translates to:
  /// **'El producto quedó oculto.'**
  String get productHidden;

  /// No description provided for @newProductTitle.
  ///
  /// In es, this message translates to:
  /// **'Nuevo producto'**
  String get newProductTitle;

  /// No description provided for @editProductTitle.
  ///
  /// In es, this message translates to:
  /// **'Editar producto'**
  String get editProductTitle;

  /// No description provided for @productNameLabel.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get productNameLabel;

  /// No description provided for @productNameError.
  ///
  /// In es, this message translates to:
  /// **'Escribe el nombre del producto.'**
  String get productNameError;

  /// No description provided for @priceLabel.
  ///
  /// In es, this message translates to:
  /// **'Precio en colones'**
  String get priceLabel;

  /// No description provided for @priceHelper.
  ///
  /// In es, this message translates to:
  /// **'Solo números, sin decimales. Ej.: 2000'**
  String get priceHelper;

  /// No description provided for @priceError.
  ///
  /// In es, this message translates to:
  /// **'Escribe un precio mayor que cero.'**
  String get priceError;

  /// No description provided for @productDescriptionLabel.
  ///
  /// In es, this message translates to:
  /// **'Descripción'**
  String get productDescriptionLabel;

  /// No description provided for @addPhoto.
  ///
  /// In es, this message translates to:
  /// **'Agregar foto'**
  String get addPhoto;

  /// No description provided for @changePhoto.
  ///
  /// In es, this message translates to:
  /// **'Cambiar foto'**
  String get changePhoto;

  /// No description provided for @photoHelper.
  ///
  /// In es, this message translates to:
  /// **'JPG, PNG o WebP, hasta 5 MB.'**
  String get photoHelper;

  /// No description provided for @saveProduct.
  ///
  /// In es, this message translates to:
  /// **'Guardar producto'**
  String get saveProduct;

  /// No description provided for @productSaved.
  ///
  /// In es, this message translates to:
  /// **'Producto guardado.'**
  String get productSaved;

  /// No description provided for @photoUploadFailed.
  ///
  /// In es, this message translates to:
  /// **'El producto se guardó, pero la foto no: {reason}'**
  String photoUploadFailed(String reason);

  /// No description provided for @aiIntro.
  ///
  /// In es, this message translates to:
  /// **'Escribe con tus palabras qué vendes y te proponemos un nombre y una descripción. Tú decides qué usar.'**
  String get aiIntro;

  /// No description provided for @aiDisabled.
  ///
  /// In es, this message translates to:
  /// **'KiuPop AI no está disponible en este entorno. Puedes escribir la descripción tú mismo.'**
  String get aiDisabled;

  /// No description provided for @aiNoteHint.
  ///
  /// In es, this message translates to:
  /// **'Ej.: Rosa roja natural para regalo'**
  String get aiNoteHint;

  /// No description provided for @improveWithAi.
  ///
  /// In es, this message translates to:
  /// **'Mejorar con IA'**
  String get improveWithAi;

  /// No description provided for @aiWorking.
  ///
  /// In es, this message translates to:
  /// **'Pensando…'**
  String get aiWorking;

  /// No description provided for @aiNeedsText.
  ///
  /// In es, this message translates to:
  /// **'Escribe primero algo sobre tu producto.'**
  String get aiNeedsText;

  /// No description provided for @aiProposal.
  ///
  /// In es, this message translates to:
  /// **'Propuesta de KiuPop AI'**
  String get aiProposal;

  /// No description provided for @aiPriceUntouched.
  ///
  /// In es, this message translates to:
  /// **'El precio no lo cambia la IA: lo pones tú.'**
  String get aiPriceUntouched;

  /// No description provided for @aiUse.
  ///
  /// In es, this message translates to:
  /// **'Usar esta propuesta'**
  String get aiUse;

  /// No description provided for @aiDiscard.
  ///
  /// In es, this message translates to:
  /// **'Descartar'**
  String get aiDiscard;

  /// No description provided for @aiAccepted.
  ///
  /// In es, this message translates to:
  /// **'Listo. Revisa y edita el texto antes de guardar.'**
  String get aiAccepted;

  /// No description provided for @yourLink.
  ///
  /// In es, this message translates to:
  /// **'Tu enlace público'**
  String get yourLink;

  /// No description provided for @viewMyStore.
  ///
  /// In es, this message translates to:
  /// **'Ver mi tienda'**
  String get viewMyStore;

  /// No description provided for @copyLink.
  ///
  /// In es, this message translates to:
  /// **'Copiar enlace'**
  String get copyLink;

  /// No description provided for @linkCopied.
  ///
  /// In es, this message translates to:
  /// **'Enlace copiado.'**
  String get linkCopied;

  /// No description provided for @shareWhatsApp.
  ///
  /// In es, this message translates to:
  /// **'Compartir por WhatsApp'**
  String get shareWhatsApp;

  /// No description provided for @shareMessage.
  ///
  /// In es, this message translates to:
  /// **'¡Mira el catálogo de {store}! Haz tu pedido aquí: {link}'**
  String shareMessage(String store, String link);

  /// No description provided for @catalogPreview.
  ///
  /// In es, this message translates to:
  /// **'Así se ve tu catálogo'**
  String get catalogPreview;

  /// No description provided for @catalogPreviewEmpty.
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay productos visibles.'**
  String get catalogPreviewEmpty;

  /// No description provided for @storeNotFound.
  ///
  /// In es, this message translates to:
  /// **'No encontramos esta tienda'**
  String get storeNotFound;

  /// No description provided for @storeNotFoundBody.
  ///
  /// In es, this message translates to:
  /// **'Revisa el enlace que te compartieron.'**
  String get storeNotFoundBody;

  /// No description provided for @loadCatalogError.
  ///
  /// In es, this message translates to:
  /// **'No pudimos cargar el catálogo'**
  String get loadCatalogError;

  /// No description provided for @catalogEmpty.
  ///
  /// In es, this message translates to:
  /// **'Pronto habrá productos aquí'**
  String get catalogEmpty;

  /// No description provided for @catalogEmptyBody.
  ///
  /// In es, this message translates to:
  /// **'Esta tienda todavía no tiene productos disponibles.'**
  String get catalogEmptyBody;

  /// No description provided for @addToCart.
  ///
  /// In es, this message translates to:
  /// **'Agregar'**
  String get addToCart;

  /// No description provided for @decrease.
  ///
  /// In es, this message translates to:
  /// **'Quitar uno de {name}'**
  String decrease(String name);

  /// No description provided for @increase.
  ///
  /// In es, this message translates to:
  /// **'Agregar uno de {name}'**
  String increase(String name);

  /// No description provided for @cartItems.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Ver pedido · 1 producto} other{Ver pedido · {count} productos}}'**
  String cartItems(int count);

  /// No description provided for @yourOrder.
  ///
  /// In es, this message translates to:
  /// **'Tu pedido'**
  String get yourOrder;

  /// No description provided for @cartEmpty.
  ///
  /// In es, this message translates to:
  /// **'Tu pedido está vacío.'**
  String get cartEmpty;

  /// No description provided for @subtotal.
  ///
  /// In es, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @total.
  ///
  /// In es, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @orderDisclaimer.
  ///
  /// In es, this message translates to:
  /// **'El comercio confirma disponibilidad y precio final por WhatsApp. Aún no se ha realizado ningún pago.'**
  String get orderDisclaimer;

  /// No description provided for @orderWhatsApp.
  ///
  /// In es, this message translates to:
  /// **'Pedir por WhatsApp'**
  String get orderWhatsApp;

  /// No description provided for @orderPrepared.
  ///
  /// In es, this message translates to:
  /// **'Abrimos WhatsApp con tu pedido listo. Envíalo para que el comercio lo confirme.'**
  String get orderPrepared;

  /// No description provided for @whatsappOpenFailed.
  ///
  /// In es, this message translates to:
  /// **'No pudimos abrir WhatsApp. Revisa que tu navegador permita ventanas emergentes.'**
  String get whatsappOpenFailed;

  /// No description provided for @errorOffline.
  ///
  /// In es, this message translates to:
  /// **'No hay conexión con KiuPop. Revisa tu internet e intenta de nuevo.'**
  String get errorOffline;

  /// No description provided for @errorTimeout.
  ///
  /// In es, this message translates to:
  /// **'KiuPop tardó demasiado en responder. Intenta de nuevo.'**
  String get errorTimeout;

  /// No description provided for @errorGeneric.
  ///
  /// In es, this message translates to:
  /// **'Algo salió mal. Intenta de nuevo.'**
  String get errorGeneric;

  /// No description provided for @kiuLoginTitle.
  ///
  /// In es, this message translates to:
  /// **'Creá tu tienda con Kiu'**
  String get kiuLoginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Entrá en un clic y empezamos a conversar.'**
  String get loginSubtitle;

  /// No description provided for @loginEmulatorNotice.
  ///
  /// In es, this message translates to:
  /// **'Modo local: cuentas de prueba del emulador. No uses tu contraseña real.'**
  String get loginEmulatorNotice;

  /// No description provided for @loginDisabledNotice.
  ///
  /// In es, this message translates to:
  /// **'El inicio de sesión no está configurado en este entorno.'**
  String get loginDisabledNotice;

  /// No description provided for @loginGoogle.
  ///
  /// In es, this message translates to:
  /// **'Continuar con Google'**
  String get loginGoogle;

  /// No description provided for @loginFacebook.
  ///
  /// In es, this message translates to:
  /// **'Continuar con Facebook'**
  String get loginFacebook;

  /// No description provided for @loginFacebookSoon.
  ///
  /// In es, this message translates to:
  /// **'Facebook (pronto)'**
  String get loginFacebookSoon;

  /// No description provided for @loginFacebookPending.
  ///
  /// In es, this message translates to:
  /// **'Se activa cuando la app de Meta esté configurada.'**
  String get loginFacebookPending;

  /// No description provided for @loginOrEmail.
  ///
  /// In es, this message translates to:
  /// **'o con tu correo'**
  String get loginOrEmail;

  /// No description provided for @loginEmail.
  ///
  /// In es, this message translates to:
  /// **'Correo'**
  String get loginEmail;

  /// No description provided for @loginPassword.
  ///
  /// In es, this message translates to:
  /// **'Contraseña'**
  String get loginPassword;

  /// No description provided for @loginPasswordHelp.
  ///
  /// In es, this message translates to:
  /// **'Mínimo 6 caracteres.'**
  String get loginPasswordHelp;

  /// No description provided for @loginCreateAccount.
  ///
  /// In es, this message translates to:
  /// **'Crear cuenta'**
  String get loginCreateAccount;

  /// No description provided for @loginSignIn.
  ///
  /// In es, this message translates to:
  /// **'Entrar'**
  String get loginSignIn;

  /// No description provided for @loginHaveAccount.
  ///
  /// In es, this message translates to:
  /// **'Ya tengo cuenta · Entrar'**
  String get loginHaveAccount;

  /// No description provided for @loginNoAccount.
  ///
  /// In es, this message translates to:
  /// **'No tengo cuenta · Crear una'**
  String get loginNoAccount;

  /// No description provided for @loginLegacyKey.
  ///
  /// In es, this message translates to:
  /// **'Entrar con una clave kp_ (tiendas del POC)'**
  String get loginLegacyKey;

  /// No description provided for @authInvalidCredentials.
  ///
  /// In es, this message translates to:
  /// **'El correo o la contraseña no coinciden.'**
  String get authInvalidCredentials;

  /// No description provided for @authEmailInUse.
  ///
  /// In es, this message translates to:
  /// **'Ese correo ya tiene cuenta. Tocá «Entrar».'**
  String get authEmailInUse;

  /// No description provided for @authWeakPassword.
  ///
  /// In es, this message translates to:
  /// **'Usá al menos 6 caracteres.'**
  String get authWeakPassword;

  /// No description provided for @authInvalidEmail.
  ///
  /// In es, this message translates to:
  /// **'Escribí un correo válido.'**
  String get authInvalidEmail;

  /// No description provided for @authProviderDisabled.
  ///
  /// In es, this message translates to:
  /// **'Este método de ingreso no está habilitado todavía.'**
  String get authProviderDisabled;

  /// No description provided for @authNetwork.
  ///
  /// In es, this message translates to:
  /// **'Sin conexión. Revisá tu internet e intentá de nuevo.'**
  String get authNetwork;

  /// No description provided for @authUnknown.
  ///
  /// In es, this message translates to:
  /// **'No pudimos iniciar sesión. Intentá de nuevo.'**
  String get authUnknown;

  /// No description provided for @kiuPopWord.
  ///
  /// In es, this message translates to:
  /// **'¡POP!'**
  String get kiuPopWord;

  /// No description provided for @kiuSemantic.
  ///
  /// In es, this message translates to:
  /// **'Kiu, el asistente de KiuPop'**
  String get kiuSemantic;

  /// No description provided for @kiuThinking.
  ///
  /// In es, this message translates to:
  /// **'Kiu está pensando…'**
  String get kiuThinking;

  /// No description provided for @kiuLoadError.
  ///
  /// In es, this message translates to:
  /// **'No pudimos abrir tu conversación con Kiu'**
  String get kiuLoadError;

  /// No description provided for @aiModeClaude.
  ///
  /// In es, this message translates to:
  /// **'IA'**
  String get aiModeClaude;

  /// No description provided for @aiModeLocal.
  ///
  /// In es, this message translates to:
  /// **'Modo local'**
  String get aiModeLocal;

  /// No description provided for @aiModeClaudeHelp.
  ///
  /// In es, this message translates to:
  /// **'Kiu usa un modelo de IA para entenderte.'**
  String get aiModeClaudeHelp;

  /// No description provided for @aiModeLocalHelp.
  ///
  /// In es, this message translates to:
  /// **'Sin IA conectada: Kiu usa reglas locales y nunca inventa datos.'**
  String get aiModeLocalHelp;

  /// No description provided for @stageListening.
  ///
  /// In es, this message translates to:
  /// **'Kiu te escucha'**
  String get stageListening;

  /// No description provided for @stageBuilding.
  ///
  /// In es, this message translates to:
  /// **'Armando tu tienda… {percent}%'**
  String stageBuilding(int percent);

  /// No description provided for @stageReady.
  ///
  /// In es, this message translates to:
  /// **'¡Tu tienda está lista!'**
  String get stageReady;

  /// No description provided for @stagePublished.
  ///
  /// In es, this message translates to:
  /// **'Tu tienda está publicada'**
  String get stagePublished;

  /// No description provided for @skipAnimation.
  ///
  /// In es, this message translates to:
  /// **'Saltar animación'**
  String get skipAnimation;

  /// No description provided for @seePreview.
  ///
  /// In es, this message translates to:
  /// **'Ver vista previa'**
  String get seePreview;

  /// No description provided for @taskDone.
  ///
  /// In es, this message translates to:
  /// **'listo'**
  String get taskDone;

  /// No description provided for @taskRunning.
  ///
  /// In es, this message translates to:
  /// **'en proceso'**
  String get taskRunning;

  /// No description provided for @taskNeedsInput.
  ///
  /// In es, this message translates to:
  /// **'necesita tu respuesta'**
  String get taskNeedsInput;

  /// No description provided for @taskSkipped.
  ///
  /// In es, this message translates to:
  /// **'omitido'**
  String get taskSkipped;

  /// No description provided for @taskFailed.
  ///
  /// In es, this message translates to:
  /// **'no se pudo completar'**
  String get taskFailed;

  /// No description provided for @taskPending.
  ///
  /// In es, this message translates to:
  /// **'pendiente'**
  String get taskPending;

  /// No description provided for @composerHintFirst.
  ///
  /// In es, this message translates to:
  /// **'Ej.: Soy Florería Bella, vendo flores y arreglos…'**
  String get composerHintFirst;

  /// No description provided for @composerHintAnswer.
  ///
  /// In es, this message translates to:
  /// **'Escribí tu respuesta…'**
  String get composerHintAnswer;

  /// No description provided for @skipQuestion.
  ///
  /// In es, this message translates to:
  /// **'Omitir esta pregunta'**
  String get skipQuestion;

  /// No description provided for @send.
  ///
  /// In es, this message translates to:
  /// **'Enviar'**
  String get send;

  /// No description provided for @publishCta.
  ///
  /// In es, this message translates to:
  /// **'Publicar mi tienda'**
  String get publishCta;

  /// No description provided for @publishConfirmTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Publicamos tu tienda?'**
  String get publishConfirmTitle;

  /// No description provided for @publishConfirmBody.
  ///
  /// In es, this message translates to:
  /// **'Cualquier persona con el enlace podrá verla y hacerte pedidos por WhatsApp. Los pagos en línea reales siguen apagados.'**
  String get publishConfirmBody;

  /// No description provided for @publishConfirmCta.
  ///
  /// In es, this message translates to:
  /// **'Sí, publicar'**
  String get publishConfirmCta;

  /// No description provided for @publishFailed.
  ///
  /// In es, this message translates to:
  /// **'No pudimos publicar. Intentá de nuevo.'**
  String get publishFailed;

  /// No description provided for @previewTitle.
  ///
  /// In es, this message translates to:
  /// **'Vista previa'**
  String get previewTitle;

  /// No description provided for @previewDraft.
  ///
  /// In es, this message translates to:
  /// **'Vista previa · aún no es pública'**
  String get previewDraft;

  /// No description provided for @previewPublished.
  ///
  /// In es, this message translates to:
  /// **'Así ven tu tienda tus clientes'**
  String get previewPublished;

  /// No description provided for @previewEmpty.
  ///
  /// In es, this message translates to:
  /// **'Contale a Kiu sobre tu negocio y acá vas a ver tu tienda.'**
  String get previewEmpty;

  /// No description provided for @previewBuilding.
  ///
  /// In es, this message translates to:
  /// **'Kiu está armando tu tienda…'**
  String get previewBuilding;

  /// No description provided for @shareTitle.
  ///
  /// In es, this message translates to:
  /// **'¡Compartí tu tienda!'**
  String get shareTitle;

  /// No description provided for @shareText.
  ///
  /// In es, this message translates to:
  /// **'Mirá la tienda de {name}'**
  String shareText(String name);

  /// No description provided for @share.
  ///
  /// In es, this message translates to:
  /// **'Compartir'**
  String get share;

  /// No description provided for @openMyStore.
  ///
  /// In es, this message translates to:
  /// **'Ver mi tienda'**
  String get openMyStore;

  /// No description provided for @addPhotosInAdmin.
  ///
  /// In es, this message translates to:
  /// **'Agregar fotos y editar'**
  String get addPhotosInAdmin;

  /// No description provided for @noStoreYet.
  ///
  /// In es, this message translates to:
  /// **'Todavía no tenés una tienda'**
  String get noStoreYet;

  /// No description provided for @noStoreYetBody.
  ///
  /// In es, this message translates to:
  /// **'Contale a Kiu sobre tu negocio y la creamos en minutos.'**
  String get noStoreYetBody;

  /// No description provided for @createWithKiu.
  ///
  /// In es, this message translates to:
  /// **'Crear con Kiu'**
  String get createWithKiu;

  /// No description provided for @cancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get cancel;

  /// No description provided for @sfCatalog.
  ///
  /// In es, this message translates to:
  /// **'Catálogo'**
  String get sfCatalog;

  /// No description provided for @sfFeatured.
  ///
  /// In es, this message translates to:
  /// **'Destacados'**
  String get sfFeatured;

  /// No description provided for @sfWriteWhatsApp.
  ///
  /// In es, this message translates to:
  /// **'Escribir por WhatsApp'**
  String get sfWriteWhatsApp;

  /// No description provided for @sfAvailableWhenPublished.
  ///
  /// In es, this message translates to:
  /// **'WhatsApp (al publicar)'**
  String get sfAvailableWhenPublished;

  /// No description provided for @sfDelivery.
  ///
  /// In es, this message translates to:
  /// **'Entregas'**
  String get sfDelivery;

  /// No description provided for @sfDeliveryHome.
  ///
  /// In es, this message translates to:
  /// **'Entrega a domicilio'**
  String get sfDeliveryHome;

  /// No description provided for @sfDeliveryPickup.
  ///
  /// In es, this message translates to:
  /// **'Retiro disponible'**
  String get sfDeliveryPickup;

  /// No description provided for @sfDeliveryCoordinate.
  ///
  /// In es, this message translates to:
  /// **'Coordinamos la entrega por WhatsApp.'**
  String get sfDeliveryCoordinate;

  /// No description provided for @sfPaymentsToCoordinate.
  ///
  /// In es, this message translates to:
  /// **'Pagos a coordinar: {methods}'**
  String sfPaymentsToCoordinate(String methods);

  /// No description provided for @sfRealPaymentsPending.
  ///
  /// In es, this message translates to:
  /// **'Pagos en línea reales: pendientes de activar.'**
  String get sfRealPaymentsPending;

  /// No description provided for @sfContact.
  ///
  /// In es, this message translates to:
  /// **'Contacto'**
  String get sfContact;

  /// No description provided for @sfMadeWith.
  ///
  /// In es, this message translates to:
  /// **'Hecho con KiuPop'**
  String get sfMadeWith;

  /// No description provided for @sfDraftBadge.
  ///
  /// In es, this message translates to:
  /// **'Vista previa · borrador'**
  String get sfDraftBadge;

  /// No description provided for @sfTestCheckout.
  ///
  /// In es, this message translates to:
  /// **'Pagar en línea (prueba)'**
  String get sfTestCheckout;

  /// No description provided for @checkoutTitle.
  ///
  /// In es, this message translates to:
  /// **'Pago de prueba'**
  String get checkoutTitle;

  /// No description provided for @checkoutTestNotice.
  ///
  /// In es, this message translates to:
  /// **'Modo de prueba: no se cobra dinero real.'**
  String get checkoutTestNotice;

  /// No description provided for @checkoutSimulateApprove.
  ///
  /// In es, this message translates to:
  /// **'Simular pago aprobado'**
  String get checkoutSimulateApprove;

  /// No description provided for @checkoutSimulateDecline.
  ///
  /// In es, this message translates to:
  /// **'Simular rechazo'**
  String get checkoutSimulateDecline;

  /// No description provided for @checkoutApproved.
  ///
  /// In es, this message translates to:
  /// **'Pago de prueba aprobado'**
  String get checkoutApproved;

  /// No description provided for @checkoutDeclined.
  ///
  /// In es, this message translates to:
  /// **'Pago de prueba rechazado'**
  String get checkoutDeclined;

  /// No description provided for @checkoutNoRealMoney.
  ///
  /// In es, this message translates to:
  /// **'No se cobró dinero real. El comercio confirma tu pedido por WhatsApp.'**
  String get checkoutNoRealMoney;

  /// No description provided for @catFlores.
  ///
  /// In es, this message translates to:
  /// **'Flores'**
  String get catFlores;

  /// No description provided for @catReposteria.
  ///
  /// In es, this message translates to:
  /// **'Repostería'**
  String get catReposteria;

  /// No description provided for @catComida.
  ///
  /// In es, this message translates to:
  /// **'Comida'**
  String get catComida;

  /// No description provided for @catRopa.
  ///
  /// In es, this message translates to:
  /// **'Ropa'**
  String get catRopa;

  /// No description provided for @catBelleza.
  ///
  /// In es, this message translates to:
  /// **'Belleza'**
  String get catBelleza;

  /// No description provided for @catArtesania.
  ///
  /// In es, this message translates to:
  /// **'Artesanía'**
  String get catArtesania;

  /// No description provided for @catMascotas.
  ///
  /// In es, this message translates to:
  /// **'Mascotas'**
  String get catMascotas;

  /// No description provided for @catPlantas.
  ///
  /// In es, this message translates to:
  /// **'Plantas'**
  String get catPlantas;

  /// No description provided for @catTecnologia.
  ///
  /// In es, this message translates to:
  /// **'Tecnología'**
  String get catTecnologia;

  /// No description provided for @catOtro.
  ///
  /// In es, this message translates to:
  /// **'Tienda'**
  String get catOtro;

  /// No description provided for @createAnotherStore.
  ///
  /// In es, this message translates to:
  /// **'Crear otra tienda'**
  String get createAnotherStore;

  /// No description provided for @attachFiles.
  ///
  /// In es, this message translates to:
  /// **'Compartir fotos o tu catálogo (Excel, CSV, texto o PDF)'**
  String get attachFiles;

  /// No description provided for @fileTooMany.
  ///
  /// In es, this message translates to:
  /// **'{name}: ya compartiste el máximo de archivos.'**
  String fileTooMany(String name);

  /// No description provided for @fileTooBig.
  ///
  /// In es, this message translates to:
  /// **'{name}: es demasiado grande (máximo 20 MB).'**
  String fileTooBig(String name);

  /// No description provided for @uploadingFiles.
  ///
  /// In es, this message translates to:
  /// **'Subiendo {count, plural, =1{1 archivo} other{{count} archivos}}…'**
  String uploadingFiles(int count);

  /// No description provided for @fileReceived.
  ///
  /// In es, this message translates to:
  /// **'recibido'**
  String get fileReceived;

  /// No description provided for @fileProcessing.
  ///
  /// In es, this message translates to:
  /// **'procesando'**
  String get fileProcessing;

  /// No description provided for @fileProcessed.
  ///
  /// In es, this message translates to:
  /// **'listo'**
  String get fileProcessed;

  /// No description provided for @fileNeedsReview.
  ///
  /// In es, this message translates to:
  /// **'revisar'**
  String get fileNeedsReview;

  /// No description provided for @fileError.
  ///
  /// In es, this message translates to:
  /// **'error'**
  String get fileError;

  /// No description provided for @googleTestTitle.
  ///
  /// In es, this message translates to:
  /// **'Cuenta de Google de prueba'**
  String get googleTestTitle;

  /// No description provided for @googleTestBody.
  ///
  /// In es, this message translates to:
  /// **'Modo local: el emulador crea una cuenta de prueba. No se usa ninguna cuenta real de Google.'**
  String get googleTestBody;

  /// No description provided for @googleTestName.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get googleTestName;

  /// No description provided for @micStart.
  ///
  /// In es, this message translates to:
  /// **'Dictar (tu navegador transcribe; no guardamos audio)'**
  String get micStart;

  /// No description provided for @micStop.
  ///
  /// In es, this message translates to:
  /// **'Detener dictado'**
  String get micStop;

  /// No description provided for @micDenied.
  ///
  /// In es, this message translates to:
  /// **'Activá el permiso del micrófono para dictar. También podés escribir.'**
  String get micDenied;

  /// No description provided for @micError.
  ///
  /// In es, this message translates to:
  /// **'No pude escucharte. Probá de nuevo o escribime.'**
  String get micError;

  /// No description provided for @uploadCatalog.
  ///
  /// In es, this message translates to:
  /// **'Subir catálogo (Excel, CSV o texto)'**
  String get uploadCatalog;

  /// No description provided for @themeSystem.
  ///
  /// In es, this message translates to:
  /// **'Tema: automático (según tu dispositivo)'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In es, this message translates to:
  /// **'Tema: claro'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In es, this message translates to:
  /// **'Tema: oscuro'**
  String get themeDark;

  /// No description provided for @kiuSaid.
  ///
  /// In es, this message translates to:
  /// **'Kiu dijo'**
  String get kiuSaid;

  /// No description provided for @youSaid.
  ///
  /// In es, this message translates to:
  /// **'Tú dijiste'**
  String get youSaid;

  /// No description provided for @scrollToLatest.
  ///
  /// In es, this message translates to:
  /// **'Ir al último mensaje'**
  String get scrollToLatest;

  /// No description provided for @welcomeLead.
  ///
  /// In es, this message translates to:
  /// **'Contásela a Kiu y mirá cómo se convierte en una tienda lista para compartir.'**
  String get welcomeLead;

  /// No description provided for @loginHowItWorks.
  ///
  /// In es, this message translates to:
  /// **'Así funciona'**
  String get loginHowItWorks;

  /// No description provided for @loginJustLooking.
  ///
  /// In es, this message translates to:
  /// **'¿Solo querés mirar? Ver una tienda de ejemplo'**
  String get loginJustLooking;

  /// No description provided for @settingsTitle.
  ///
  /// In es, this message translates to:
  /// **'Ajustes'**
  String get settingsTitle;

  /// No description provided for @themeShortSystem.
  ///
  /// In es, this message translates to:
  /// **'Automático'**
  String get themeShortSystem;

  /// No description provided for @themeShortLight.
  ///
  /// In es, this message translates to:
  /// **'Claro'**
  String get themeShortLight;

  /// No description provided for @themeShortDark.
  ///
  /// In es, this message translates to:
  /// **'Oscuro'**
  String get themeShortDark;

  /// No description provided for @themeLabel.
  ///
  /// In es, this message translates to:
  /// **'Apariencia'**
  String get themeLabel;

  /// No description provided for @kiuBrainLabel.
  ///
  /// In es, this message translates to:
  /// **'Cómo piensa Kiu'**
  String get kiuBrainLabel;

  /// No description provided for @stageListeningHint.
  ///
  /// In es, this message translates to:
  /// **'Contame qué vendés y cómo se llama tu negocio.'**
  String get stageListeningHint;

  /// No description provided for @stageBuildingHint.
  ///
  /// In es, this message translates to:
  /// **'Kiu arma tu catálogo con lo que le contaste.'**
  String get stageBuildingHint;

  /// No description provided for @stageReadyHint.
  ///
  /// In es, this message translates to:
  /// **'Mirala antes de publicarla. Vos decidís cuándo.'**
  String get stageReadyHint;

  /// No description provided for @stagePublishedHint.
  ///
  /// In es, this message translates to:
  /// **'Ya podés compartirla y recibir pedidos.'**
  String get stagePublishedHint;

  /// No description provided for @kiuDiagnosis.
  ///
  /// In es, this message translates to:
  /// **'Diagnóstico de Kiu'**
  String get kiuDiagnosis;

  /// No description provided for @paywallTestBadge.
  ///
  /// In es, this message translates to:
  /// **'Modo demostración'**
  String get paywallTestBadge;

  /// No description provided for @paywallTitle.
  ///
  /// In es, this message translates to:
  /// **'Tu tienda está lista para dar el siguiente paso.'**
  String get paywallTitle;

  /// No description provided for @paywallLead.
  ///
  /// In es, this message translates to:
  /// **'Ya tenés el diseño, el catálogo y los productos organizados. Activá KiuPop para compartir tu tienda y empezar a recibir oportunidades de venta.'**
  String get paywallLead;

  /// No description provided for @paywallPerMonth.
  ///
  /// In es, this message translates to:
  /// **' / mes'**
  String get paywallPerMonth;

  /// No description provided for @paywallPerStore.
  ///
  /// In es, this message translates to:
  /// **'por tienda activa. Si la pausas, no pagas.'**
  String get paywallPerStore;

  /// No description provided for @paywallIncludesLink.
  ///
  /// In es, this message translates to:
  /// **'Enlace público para compartir en redes'**
  String get paywallIncludesLink;

  /// No description provided for @paywallIncludesWhatsApp.
  ///
  /// In es, this message translates to:
  /// **'Pedidos directo a tu WhatsApp'**
  String get paywallIncludesWhatsApp;

  /// No description provided for @paywallIncludesQr.
  ///
  /// In es, this message translates to:
  /// **'Catálogo con link y código QR'**
  String get paywallIncludesQr;

  /// No description provided for @paywallTestCard.
  ///
  /// In es, this message translates to:
  /// **'Tarjeta de prueba •••• 4242'**
  String get paywallTestCard;

  /// No description provided for @paywallFreeNote.
  ///
  /// In es, this message translates to:
  /// **'Ver y ajustar tu tienda con Kiu no tiene costo.'**
  String get paywallFreeNote;

  /// No description provided for @paywallPayCta.
  ///
  /// In es, this message translates to:
  /// **'Pagar {price} y publicar'**
  String paywallPayCta(String price);

  /// No description provided for @paywallPaying.
  ///
  /// In es, this message translates to:
  /// **'Simulando activación…'**
  String get paywallPaying;

  /// No description provided for @paywallLater.
  ///
  /// In es, this message translates to:
  /// **'Ahora no'**
  String get paywallLater;

  /// No description provided for @paywallFailed.
  ///
  /// In es, this message translates to:
  /// **'No pudimos activar tu plan. Intenta de nuevo.'**
  String get paywallFailed;

  /// No description provided for @paywallActivated.
  ///
  /// In es, this message translates to:
  /// **'Activación de prueba lista: no se cargó ningún monto. Publicando tu tienda…'**
  String get paywallActivated;

  /// No description provided for @voiceTitle.
  ///
  /// In es, this message translates to:
  /// **'Hablar con Kiu'**
  String get voiceTitle;

  /// No description provided for @voiceIdleHint.
  ///
  /// In es, this message translates to:
  /// **'Contame qué vendés, cómo se llama tu negocio y tus precios. Hasta {seconds} segundos.'**
  String voiceIdleHint(int seconds);

  /// No description provided for @voiceTapToRecord.
  ///
  /// In es, this message translates to:
  /// **'Tocá para grabar'**
  String get voiceTapToRecord;

  /// No description provided for @voiceStart.
  ///
  /// In es, this message translates to:
  /// **'Empezar a grabar'**
  String get voiceStart;

  /// No description provided for @voiceStop.
  ///
  /// In es, this message translates to:
  /// **'Detener grabación'**
  String get voiceStop;

  /// No description provided for @voiceRecording.
  ///
  /// In es, this message translates to:
  /// **'Grabando…'**
  String get voiceRecording;

  /// No description provided for @voiceDiscard.
  ///
  /// In es, this message translates to:
  /// **'Descartar'**
  String get voiceDiscard;

  /// No description provided for @voicePlay.
  ///
  /// In es, this message translates to:
  /// **'Escuchar'**
  String get voicePlay;

  /// No description provided for @voicePause.
  ///
  /// In es, this message translates to:
  /// **'Pausar'**
  String get voicePause;

  /// No description provided for @voiceRerecord.
  ///
  /// In es, this message translates to:
  /// **'Grabar de nuevo'**
  String get voiceRerecord;

  /// No description provided for @voiceDelete.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get voiceDelete;

  /// No description provided for @voiceTranscribe.
  ///
  /// In es, this message translates to:
  /// **'Transcribir'**
  String get voiceTranscribe;

  /// No description provided for @voiceTranscribing.
  ///
  /// In es, this message translates to:
  /// **'Kiu está escuchando tu audio…'**
  String get voiceTranscribing;

  /// No description provided for @voiceReviewTitle.
  ///
  /// In es, this message translates to:
  /// **'Esto entendí'**
  String get voiceReviewTitle;

  /// No description provided for @voiceReviewHint.
  ///
  /// In es, this message translates to:
  /// **'Corregí nombres, precios o cantidades si hace falta. Kiu recibe solo este texto.'**
  String get voiceReviewHint;

  /// No description provided for @voiceTranscriptLabel.
  ///
  /// In es, this message translates to:
  /// **'Tu idea, en texto'**
  String get voiceTranscriptLabel;

  /// No description provided for @voiceSend.
  ///
  /// In es, this message translates to:
  /// **'Enviar a Kiu'**
  String get voiceSend;

  /// No description provided for @voiceWriteInstead.
  ///
  /// In es, this message translates to:
  /// **'Prefiero escribir'**
  String get voiceWriteInstead;

  /// No description provided for @voicePermissionDenied.
  ///
  /// In es, this message translates to:
  /// **'Necesito permiso para usar el micrófono. Activalo en la configuración del navegador o del teléfono, o escribime.'**
  String get voicePermissionDenied;

  /// No description provided for @voiceMicError.
  ///
  /// In es, this message translates to:
  /// **'No pude usar el micrófono. Probá de nuevo o escribime.'**
  String get voiceMicError;

  /// No description provided for @voiceTooShort.
  ///
  /// In es, this message translates to:
  /// **'El audio quedó muy corto. Contame un poco más.'**
  String get voiceTooShort;

  /// No description provided for @voiceEmptyTranscript.
  ///
  /// In es, this message translates to:
  /// **'Escribí o corregí el texto antes de enviarlo.'**
  String get voiceEmptyTranscript;

  /// No description provided for @voiceProvider.
  ///
  /// In es, this message translates to:
  /// **'Transcripción con {provider}. El audio no se guarda.'**
  String voiceProvider(String provider);

  /// No description provided for @voiceUnavailable.
  ///
  /// In es, this message translates to:
  /// **'La transcripción de audio no está disponible ahora. Podés escribirle a Kiu.'**
  String get voiceUnavailable;

  /// No description provided for @intakeTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Cómo querés contarle tu idea a Kiu?'**
  String get intakeTitle;

  /// No description provided for @intakeFree.
  ///
  /// In es, this message translates to:
  /// **'Contame qué imaginás. Crear tu primera propuesta no tiene costo.'**
  String get intakeFree;

  /// No description provided for @intakeVoiceTitle.
  ///
  /// In es, this message translates to:
  /// **'Hablar con Kiu'**
  String get intakeVoiceTitle;

  /// No description provided for @intakeVoiceBody.
  ///
  /// In es, this message translates to:
  /// **'Grabá un audio y contame qué vendés. Yo me encargo del resto.'**
  String get intakeVoiceBody;

  /// No description provided for @intakeTextTitle.
  ///
  /// In es, this message translates to:
  /// **'Escribir mi idea'**
  String get intakeTextTitle;

  /// No description provided for @intakeTextBody.
  ///
  /// In es, this message translates to:
  /// **'Escribí una descripción de tu negocio.'**
  String get intakeTextBody;

  /// No description provided for @intakeVoiceOff.
  ///
  /// In es, this message translates to:
  /// **'Audio no disponible ahora'**
  String get intakeVoiceOff;

  /// No description provided for @revealTitle.
  ///
  /// In es, this message translates to:
  /// **'¡POP! Tu tienda ya tomó forma.'**
  String get revealTitle;

  /// No description provided for @revealBody.
  ///
  /// In es, this message translates to:
  /// **'Kiu organizó tu negocio y preparó una tienda diseñada para vos.'**
  String get revealBody;

  /// No description provided for @revealExplore.
  ///
  /// In es, this message translates to:
  /// **'Explorar mi tienda'**
  String get revealExplore;

  /// No description provided for @revealAdjust.
  ///
  /// In es, this message translates to:
  /// **'Hacer un ajuste'**
  String get revealAdjust;

  /// No description provided for @revealContinue.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get revealContinue;

  /// No description provided for @adjustHint.
  ///
  /// In es, this message translates to:
  /// **'Contale a Kiu qué querés cambiar: colores, nombres, precios…'**
  String get adjustHint;

  /// No description provided for @uploadSending.
  ///
  /// In es, this message translates to:
  /// **'Subiendo {name}…'**
  String uploadSending(String name);

  /// No description provided for @uploadCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar subida de {name}'**
  String uploadCancel(String name);

  /// No description provided for @uploadRetry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get uploadRetry;

  /// No description provided for @uploadRemove.
  ///
  /// In es, this message translates to:
  /// **'Quitar'**
  String get uploadRemove;

  /// No description provided for @uploadCancelled.
  ///
  /// In es, this message translates to:
  /// **'{name}: subida cancelada.'**
  String uploadCancelled(String name);

  /// No description provided for @fileTooManyTotal.
  ///
  /// In es, this message translates to:
  /// **'{name}: con este archivo superás los {mb} MB por tienda.'**
  String fileTooManyTotal(String name, int mb);

  /// No description provided for @voiceNote.
  ///
  /// In es, this message translates to:
  /// **'Nota de voz'**
  String get voiceNote;

  /// No description provided for @paywallDemoNotice.
  ///
  /// In es, this message translates to:
  /// **'Modo demostración. KiuPop todavía no procesa suscripciones ni cobros reales. Esta activación es simulada y no se cargará ningún monto.'**
  String get paywallDemoNotice;

  /// No description provided for @paywallPlanName.
  ///
  /// In es, this message translates to:
  /// **'Plan de demostración'**
  String get paywallPlanName;

  /// No description provided for @paywallPriceNote.
  ///
  /// In es, this message translates to:
  /// **'Precio de referencia para la demo. No se cobra.'**
  String get paywallPriceNote;

  /// No description provided for @paywallIncludedTitle.
  ///
  /// In es, this message translates to:
  /// **'Incluido hoy'**
  String get paywallIncludedTitle;

  /// No description provided for @paywallBenefitCatalog.
  ///
  /// In es, this message translates to:
  /// **'Catálogo público'**
  String get paywallBenefitCatalog;

  /// No description provided for @paywallBenefitLinks.
  ///
  /// In es, this message translates to:
  /// **'Enlaces compartibles'**
  String get paywallBenefitLinks;

  /// No description provided for @paywallBenefitCart.
  ///
  /// In es, this message translates to:
  /// **'Carrito'**
  String get paywallBenefitCart;

  /// No description provided for @paywallBenefitWhatsApp.
  ///
  /// In es, this message translates to:
  /// **'Pedidos por WhatsApp'**
  String get paywallBenefitWhatsApp;

  /// No description provided for @paywallBenefitAdmin.
  ///
  /// In es, this message translates to:
  /// **'Administración de productos'**
  String get paywallBenefitAdmin;

  /// No description provided for @paywallBenefitDesign.
  ///
  /// In es, this message translates to:
  /// **'Personalización visual'**
  String get paywallBenefitDesign;

  /// No description provided for @paywallBenefitKiu.
  ///
  /// In es, this message translates to:
  /// **'Asistencia de Kiu'**
  String get paywallBenefitKiu;

  /// No description provided for @paywallSoonTitle.
  ///
  /// In es, this message translates to:
  /// **'Próximamente'**
  String get paywallSoonTitle;

  /// No description provided for @paywallSoonPayments.
  ///
  /// In es, this message translates to:
  /// **'Pagos en línea reales'**
  String get paywallSoonPayments;

  /// No description provided for @paywallSoonIntegrations.
  ///
  /// In es, this message translates to:
  /// **'Integraciones avanzadas'**
  String get paywallSoonIntegrations;

  /// No description provided for @paywallSimulateCta.
  ///
  /// In es, this message translates to:
  /// **'Simular activación'**
  String get paywallSimulateCta;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
