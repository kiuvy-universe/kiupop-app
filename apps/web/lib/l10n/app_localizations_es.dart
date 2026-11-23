// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'KiuPop';

  @override
  String get tagline => 'Tu tienda empieza con una idea.';

  @override
  String get welcomeSubtitle =>
      'Kiu entiende lo que vendés, te hace unas pocas preguntas y crea una tienda preciosa, lista para compartir y recibir pedidos por WhatsApp.';

  @override
  String get welcomeStep1 => 'Entrá con Google o tu correo en un clic.';

  @override
  String get welcomeStep2 => 'Contale a Kiu qué vendés, con tus palabras.';

  @override
  String get welcomeStep3 =>
      'Mirá tu tienda inflarse… ¡POP! Compartila y recibí pedidos.';

  @override
  String get createStoreCta => 'Crear mi tienda';

  @override
  String get haveStoreCta => 'Ya tengo cuenta';

  @override
  String get seeDemoStore => 'Ver una tienda de ejemplo';

  @override
  String get back => 'Volver';

  @override
  String get close => 'Cerrar';

  @override
  String get retry => 'Reintentar';

  @override
  String get show => 'Mostrar';

  @override
  String get hide => 'Ocultar';

  @override
  String get createStoreTitle => 'Crea tu tienda';

  @override
  String get createStoreIntro =>
      'Solo necesitamos dos datos. Podrás cambiar todo después.';

  @override
  String get storeNameLabel => 'Nombre del negocio';

  @override
  String get storeNameHint => 'Ej.: Flores de Occidente';

  @override
  String get storeNameError =>
      'Escribe el nombre de tu negocio (mínimo 2 letras).';

  @override
  String get whatsappLabel => 'WhatsApp para recibir pedidos';

  @override
  String get whatsappHelper =>
      'Número de Costa Rica (8 dígitos) o internacional con +';

  @override
  String get whatsappError => 'Escribe un número de WhatsApp válido.';

  @override
  String get storeDescriptionLabel => 'Descripción (opcional)';

  @override
  String get storeDescriptionHint => '¿Qué vendes? ¿Dónde estás?';

  @override
  String get createStoreSubmit => 'Crear mi tienda';

  @override
  String get storeReadyTitle => '¡Tu tienda está lista!';

  @override
  String storeReadyBody(String name) {
    return '$name ya tiene su catálogo. Este es tu enlace público:';
  }

  @override
  String get credentialTitle => 'Guarda tu clave de administrador';

  @override
  String get credentialWarning =>
      'Con esta clave vuelves a editar tu tienda. Guárdala en un lugar seguro: no la mostraremos de nuevo y en esta versión no se puede recuperar.';

  @override
  String get copyCredential => 'Copiar clave';

  @override
  String get credentialCopied => 'Clave copiada. Guárdala en un lugar seguro.';

  @override
  String get credentialSavedCheck => 'Ya guardé mi clave';

  @override
  String get continueToProducts => 'Continuar a mis productos';

  @override
  String get loginTitle => 'Entrar a mi tienda';

  @override
  String get loginIntro =>
      'Pega la clave de administrador que guardaste al crear tu tienda.';

  @override
  String get credentialLabel => 'Clave de administrador';

  @override
  String get credentialInvalid =>
      'La clave no es válida. Revisa que la copiaste completa.';

  @override
  String get loginSubmit => 'Entrar';

  @override
  String get loginRecoveryNote =>
      '¿Perdiste tu clave? En esta versión de prueba no se puede recuperar.';

  @override
  String get signOut => 'Salir';

  @override
  String get tabProducts => 'Productos';

  @override
  String get tabMyStore => 'Mi tienda';

  @override
  String get addProduct => 'Agregar producto';

  @override
  String get loadProductsError => 'No pudimos cargar tus productos';

  @override
  String get noProductsTitle => 'Agrega tu primer producto';

  @override
  String get noProductsBody =>
      'Toca «Agregar producto». Con tres productos ya puedes compartir tu tienda.';

  @override
  String productsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count productos',
      one: '1 producto',
    );
    return '$_temp0';
  }

  @override
  String get visibleInStore => 'Visible en tu tienda';

  @override
  String get hiddenFromStore => 'Oculto';

  @override
  String availableToggle(String name) {
    return 'Mostrar $name en la tienda';
  }

  @override
  String get productShown => 'El producto ahora se ve en tu tienda.';

  @override
  String get productHidden => 'El producto quedó oculto.';

  @override
  String get newProductTitle => 'Nuevo producto';

  @override
  String get editProductTitle => 'Editar producto';

  @override
  String get productNameLabel => 'Nombre';

  @override
  String get productNameError => 'Escribe el nombre del producto.';

  @override
  String get priceLabel => 'Precio en colones';

  @override
  String get priceHelper => 'Solo números, sin decimales. Ej.: 2000';

  @override
  String get priceError => 'Escribe un precio mayor que cero.';

  @override
  String get productDescriptionLabel => 'Descripción';

  @override
  String get addPhoto => 'Agregar foto';

  @override
  String get changePhoto => 'Cambiar foto';

  @override
  String get photoHelper => 'JPG, PNG o WebP, hasta 5 MB.';

  @override
  String get saveProduct => 'Guardar producto';

  @override
  String get productSaved => 'Producto guardado.';

  @override
  String photoUploadFailed(String reason) {
    return 'El producto se guardó, pero la foto no: $reason';
  }

  @override
  String get aiIntro =>
      'Escribe con tus palabras qué vendes y te proponemos un nombre y una descripción. Tú decides qué usar.';

  @override
  String get aiDisabled =>
      'KiuPop AI no está disponible en este entorno. Puedes escribir la descripción tú mismo.';

  @override
  String get aiNoteHint => 'Ej.: Rosa roja natural para regalo';

  @override
  String get improveWithAi => 'Mejorar con IA';

  @override
  String get aiWorking => 'Pensando…';

  @override
  String get aiNeedsText => 'Escribe primero algo sobre tu producto.';

  @override
  String get aiProposal => 'Propuesta de KiuPop AI';

  @override
  String get aiPriceUntouched => 'El precio no lo cambia la IA: lo pones tú.';

  @override
  String get aiUse => 'Usar esta propuesta';

  @override
  String get aiDiscard => 'Descartar';

  @override
  String get aiAccepted => 'Listo. Revisa y edita el texto antes de guardar.';

  @override
  String get yourLink => 'Tu enlace público';

  @override
  String get viewMyStore => 'Ver mi tienda';

  @override
  String get copyLink => 'Copiar enlace';

  @override
  String get linkCopied => 'Enlace copiado.';

  @override
  String get shareWhatsApp => 'Compartir por WhatsApp';

  @override
  String shareMessage(String store, String link) {
    return '¡Mira el catálogo de $store! Haz tu pedido aquí: $link';
  }

  @override
  String get catalogPreview => 'Así se ve tu catálogo';

  @override
  String get catalogPreviewEmpty => 'Todavía no hay productos visibles.';

  @override
  String get storeNotFound => 'No encontramos esta tienda';

  @override
  String get storeNotFoundBody => 'Revisa el enlace que te compartieron.';

  @override
  String get loadCatalogError => 'No pudimos cargar el catálogo';

  @override
  String get catalogEmpty => 'Pronto habrá productos aquí';

  @override
  String get catalogEmptyBody =>
      'Esta tienda todavía no tiene productos disponibles.';

  @override
  String get addToCart => 'Agregar';

  @override
  String decrease(String name) {
    return 'Quitar uno de $name';
  }

  @override
  String increase(String name) {
    return 'Agregar uno de $name';
  }

  @override
  String cartItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ver pedido · $count productos',
      one: 'Ver pedido · 1 producto',
    );
    return '$_temp0';
  }

  @override
  String get yourOrder => 'Tu pedido';

  @override
  String get cartEmpty => 'Tu pedido está vacío.';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get total => 'Total';

  @override
  String get orderDisclaimer =>
      'El comercio confirma disponibilidad y precio final por WhatsApp. Aún no se ha realizado ningún pago.';

  @override
  String get orderWhatsApp => 'Pedir por WhatsApp';

  @override
  String get orderPrepared =>
      'Abrimos WhatsApp con tu pedido listo. Envíalo para que el comercio lo confirme.';

  @override
  String get whatsappOpenFailed =>
      'No pudimos abrir WhatsApp. Revisa que tu navegador permita ventanas emergentes.';

  @override
  String get errorOffline =>
      'No hay conexión con KiuPop. Revisa tu internet e intenta de nuevo.';

  @override
  String get errorTimeout =>
      'KiuPop tardó demasiado en responder. Intenta de nuevo.';

  @override
  String get errorGeneric => 'Algo salió mal. Intenta de nuevo.';

  @override
  String get kiuLoginTitle => 'Creá tu tienda con Kiu';

  @override
  String get loginSubtitle => 'Entrá en un clic y empezamos a conversar.';

  @override
  String get loginEmulatorNotice =>
      'Modo local: cuentas de prueba del emulador. No uses tu contraseña real.';

  @override
  String get loginDisabledNotice =>
      'El inicio de sesión no está configurado en este entorno.';

  @override
  String get loginGoogle => 'Continuar con Google';

  @override
  String get loginFacebook => 'Continuar con Facebook';

  @override
  String get loginFacebookSoon => 'Facebook (pronto)';

  @override
  String get loginFacebookPending =>
      'Se activa cuando la app de Meta esté configurada.';

  @override
  String get loginOrEmail => 'o con tu correo';

  @override
  String get loginEmail => 'Correo';

  @override
  String get loginPassword => 'Contraseña';

  @override
  String get loginPasswordHelp => 'Mínimo 6 caracteres.';

  @override
  String get loginCreateAccount => 'Crear cuenta';

  @override
  String get loginSignIn => 'Entrar';

  @override
  String get loginHaveAccount => 'Ya tengo cuenta · Entrar';

  @override
  String get loginNoAccount => 'No tengo cuenta · Crear una';

  @override
  String get loginLegacyKey => 'Entrar con una clave kp_ (tiendas del POC)';

  @override
  String get authInvalidCredentials =>
      'El correo o la contraseña no coinciden.';

  @override
  String get authEmailInUse => 'Ese correo ya tiene cuenta. Tocá «Entrar».';

  @override
  String get authWeakPassword => 'Usá al menos 6 caracteres.';

  @override
  String get authInvalidEmail => 'Escribí un correo válido.';

  @override
  String get authProviderDisabled =>
      'Este método de ingreso no está habilitado todavía.';

  @override
  String get authNetwork =>
      'Sin conexión. Revisá tu internet e intentá de nuevo.';

  @override
  String get authUnknown => 'No pudimos iniciar sesión. Intentá de nuevo.';

  @override
  String get kiuPopWord => '¡POP!';

  @override
  String get kiuSemantic => 'Kiu, el asistente de KiuPop';

  @override
  String get kiuThinking => 'Kiu está pensando…';

  @override
  String get kiuLoadError => 'No pudimos abrir tu conversación con Kiu';

  @override
  String get aiModeClaude => 'IA';

  @override
  String get aiModeLocal => 'Modo local';

  @override
  String get aiModeClaudeHelp => 'Kiu usa un modelo de IA para entenderte.';

  @override
  String get aiModeLocalHelp =>
      'Sin IA conectada: Kiu usa reglas locales y nunca inventa datos.';

  @override
  String get stageListening => 'Kiu te escucha';

  @override
  String stageBuilding(int percent) {
    return 'Armando tu tienda… $percent%';
  }

  @override
  String get stageReady => '¡Tu tienda está lista!';

  @override
  String get stagePublished => 'Tu tienda está publicada';

  @override
  String get skipAnimation => 'Saltar animación';

  @override
  String get seePreview => 'Ver vista previa';

  @override
  String get taskDone => 'listo';

  @override
  String get taskRunning => 'en proceso';

  @override
  String get taskNeedsInput => 'necesita tu respuesta';

  @override
  String get taskSkipped => 'omitido';

  @override
  String get taskFailed => 'no se pudo completar';

  @override
  String get taskPending => 'pendiente';

  @override
  String get composerHintFirst =>
      'Ej.: Soy Florería Bella, vendo flores y arreglos…';

  @override
  String get composerHintAnswer => 'Escribí tu respuesta…';

  @override
  String get skipQuestion => 'Omitir esta pregunta';

  @override
  String get send => 'Enviar';

  @override
  String get publishCta => 'Publicar mi tienda';

  @override
  String get publishConfirmTitle => '¿Publicamos tu tienda?';

  @override
  String get publishConfirmBody =>
      'Cualquier persona con el enlace podrá verla y hacerte pedidos por WhatsApp. Los pagos en línea reales siguen apagados.';

  @override
  String get publishConfirmCta => 'Sí, publicar';

  @override
  String get publishFailed => 'No pudimos publicar. Intentá de nuevo.';

  @override
  String get previewTitle => 'Vista previa';

  @override
  String get previewDraft => 'Vista previa · aún no es pública';

  @override
  String get previewPublished => 'Así ven tu tienda tus clientes';

  @override
  String get previewEmpty =>
      'Contale a Kiu sobre tu negocio y acá vas a ver tu tienda.';

  @override
  String get previewBuilding => 'Kiu está armando tu tienda…';

  @override
  String get shareTitle => '¡Compartí tu tienda!';

  @override
  String shareText(String name) {
    return 'Mirá la tienda de $name';
  }

  @override
  String get share => 'Compartir';

  @override
  String get openMyStore => 'Ver mi tienda';

  @override
  String get addPhotosInAdmin => 'Agregar fotos y editar';

  @override
  String get noStoreYet => 'Todavía no tenés una tienda';

  @override
  String get noStoreYetBody =>
      'Contale a Kiu sobre tu negocio y la creamos en minutos.';

  @override
  String get createWithKiu => 'Crear con Kiu';

  @override
  String get cancel => 'Cancelar';

  @override
  String get sfCatalog => 'Catálogo';

  @override
  String get sfFeatured => 'Destacados';

  @override
  String get sfWriteWhatsApp => 'Escribir por WhatsApp';

  @override
  String get sfAvailableWhenPublished => 'WhatsApp (al publicar)';

  @override
  String get sfDelivery => 'Entregas';

  @override
  String get sfDeliveryHome => 'Entrega a domicilio';

  @override
  String get sfDeliveryPickup => 'Retiro disponible';

  @override
  String get sfDeliveryCoordinate => 'Coordinamos la entrega por WhatsApp.';

  @override
  String sfPaymentsToCoordinate(String methods) {
    return 'Pagos a coordinar: $methods';
  }

  @override
  String get sfRealPaymentsPending =>
      'Pagos en línea reales: pendientes de activar.';

  @override
  String get sfContact => 'Contacto';

  @override
  String get sfMadeWith => 'Hecho con KiuPop';

  @override
  String get sfDraftBadge => 'Vista previa · borrador';

  @override
  String get sfTestCheckout => 'Pagar en línea (prueba)';

  @override
  String get checkoutTitle => 'Pago de prueba';

  @override
  String get checkoutTestNotice => 'Modo de prueba: no se cobra dinero real.';

  @override
  String get checkoutSimulateApprove => 'Simular pago aprobado';

  @override
  String get checkoutSimulateDecline => 'Simular rechazo';

  @override
  String get checkoutApproved => 'Pago de prueba aprobado';

  @override
  String get checkoutDeclined => 'Pago de prueba rechazado';

  @override
  String get checkoutNoRealMoney =>
      'No se cobró dinero real. El comercio confirma tu pedido por WhatsApp.';

  @override
  String get catFlores => 'Flores';

  @override
  String get catReposteria => 'Repostería';

  @override
  String get catComida => 'Comida';

  @override
  String get catRopa => 'Ropa';

  @override
  String get catBelleza => 'Belleza';

  @override
  String get catArtesania => 'Artesanía';

  @override
  String get catMascotas => 'Mascotas';

  @override
  String get catPlantas => 'Plantas';

  @override
  String get catTecnologia => 'Tecnología';

  @override
  String get catOtro => 'Tienda';

  @override
  String get createAnotherStore => 'Crear otra tienda';

  @override
  String get attachFiles =>
      'Compartir fotos o tu catálogo (Excel, CSV, texto o PDF)';

  @override
  String fileTooMany(String name) {
    return '$name: ya compartiste el máximo de archivos.';
  }

  @override
  String fileTooBig(String name) {
    return '$name: es demasiado grande (máximo 20 MB).';
  }

  @override
  String uploadingFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos',
      one: '1 archivo',
    );
    return 'Subiendo $_temp0…';
  }

  @override
  String get fileReceived => 'recibido';

  @override
  String get fileProcessing => 'procesando';

  @override
  String get fileProcessed => 'listo';

  @override
  String get fileNeedsReview => 'revisar';

  @override
  String get fileError => 'error';

  @override
  String get googleTestTitle => 'Cuenta de Google de prueba';

  @override
  String get googleTestBody =>
      'Modo local: el emulador crea una cuenta de prueba. No se usa ninguna cuenta real de Google.';

  @override
  String get googleTestName => 'Nombre';

  @override
  String get micStart => 'Dictar (tu navegador transcribe; no guardamos audio)';

  @override
  String get micStop => 'Detener dictado';

  @override
  String get micDenied =>
      'Activá el permiso del micrófono para dictar. También podés escribir.';

  @override
  String get micError => 'No pude escucharte. Probá de nuevo o escribime.';

  @override
  String get uploadCatalog => 'Subir catálogo (Excel, CSV o texto)';

  @override
  String get themeSystem => 'Tema: automático (según tu dispositivo)';

  @override
  String get themeLight => 'Tema: claro';

  @override
  String get themeDark => 'Tema: oscuro';

  @override
  String get kiuSaid => 'Kiu dijo';

  @override
  String get youSaid => 'Tú dijiste';

  @override
  String get scrollToLatest => 'Ir al último mensaje';

  @override
  String get welcomeLead =>
      'Contásela a Kiu y mirá cómo se convierte en una tienda lista para compartir.';

  @override
  String get loginHowItWorks => 'Así funciona';

  @override
  String get loginJustLooking =>
      '¿Solo querés mirar? Ver una tienda de ejemplo';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get themeShortSystem => 'Automático';

  @override
  String get themeShortLight => 'Claro';

  @override
  String get themeShortDark => 'Oscuro';

  @override
  String get themeLabel => 'Apariencia';

  @override
  String get kiuBrainLabel => 'Cómo piensa Kiu';

  @override
  String get stageListeningHint =>
      'Contame qué vendés y cómo se llama tu negocio.';

  @override
  String get stageBuildingHint =>
      'Kiu arma tu catálogo con lo que le contaste.';

  @override
  String get stageReadyHint =>
      'Mirala antes de publicarla. Vos decidís cuándo.';

  @override
  String get stagePublishedHint => 'Ya podés compartirla y recibir pedidos.';

  @override
  String get kiuDiagnosis => 'Diagnóstico de Kiu';

  @override
  String get paywallTestBadge => 'Modo demostración';

  @override
  String get paywallTitle => 'Tu tienda está lista para dar el siguiente paso.';

  @override
  String get paywallLead =>
      'Ya tenés el diseño, el catálogo y los productos organizados. Activá KiuPop para compartir tu tienda y empezar a recibir oportunidades de venta.';

  @override
  String get paywallPerMonth => ' / mes';

  @override
  String get paywallPerStore => 'por tienda activa. Si la pausas, no pagas.';

  @override
  String get paywallIncludesLink => 'Enlace público para compartir en redes';

  @override
  String get paywallIncludesWhatsApp => 'Pedidos directo a tu WhatsApp';

  @override
  String get paywallIncludesQr => 'Catálogo con link y código QR';

  @override
  String get paywallTestCard => 'Tarjeta de prueba •••• 4242';

  @override
  String get paywallFreeNote =>
      'Ver y ajustar tu tienda con Kiu no tiene costo.';

  @override
  String paywallPayCta(String price) {
    return 'Pagar $price y publicar';
  }

  @override
  String get paywallPaying => 'Simulando activación…';

  @override
  String get paywallLater => 'Ahora no';

  @override
  String get paywallFailed => 'No pudimos activar tu plan. Intenta de nuevo.';

  @override
  String get paywallActivated =>
      'Activación de prueba lista: no se cargó ningún monto. Publicando tu tienda…';

  @override
  String get voiceTitle => 'Hablar con Kiu';

  @override
  String voiceIdleHint(int seconds) {
    return 'Contame qué vendés, cómo se llama tu negocio y tus precios. Hasta $seconds segundos.';
  }

  @override
  String get voiceTapToRecord => 'Tocá para grabar';

  @override
  String get voiceStart => 'Empezar a grabar';

  @override
  String get voiceStop => 'Detener grabación';

  @override
  String get voiceRecording => 'Grabando…';

  @override
  String get voiceDiscard => 'Descartar';

  @override
  String get voicePlay => 'Escuchar';

  @override
  String get voicePause => 'Pausar';

  @override
  String get voiceRerecord => 'Grabar de nuevo';

  @override
  String get voiceDelete => 'Eliminar';

  @override
  String get voiceTranscribe => 'Transcribir';

  @override
  String get voiceTranscribing => 'Kiu está escuchando tu audio…';

  @override
  String get voiceReviewTitle => 'Esto entendí';

  @override
  String get voiceReviewHint =>
      'Corregí nombres, precios o cantidades si hace falta. Kiu recibe solo este texto.';

  @override
  String get voiceTranscriptLabel => 'Tu idea, en texto';

  @override
  String get voiceSend => 'Enviar a Kiu';

  @override
  String get voiceWriteInstead => 'Prefiero escribir';

  @override
  String get voicePermissionDenied =>
      'Necesito permiso para usar el micrófono. Activalo en la configuración del navegador o del teléfono, o escribime.';

  @override
  String get voiceMicError =>
      'No pude usar el micrófono. Probá de nuevo o escribime.';

  @override
  String get voiceTooShort => 'El audio quedó muy corto. Contame un poco más.';

  @override
  String get voiceEmptyTranscript =>
      'Escribí o corregí el texto antes de enviarlo.';

  @override
  String voiceProvider(String provider) {
    return 'Transcripción con $provider. El audio no se guarda.';
  }

  @override
  String get voiceUnavailable =>
      'La transcripción de audio no está disponible ahora. Podés escribirle a Kiu.';

  @override
  String get intakeTitle => '¿Cómo querés contarle tu idea a Kiu?';

  @override
  String get intakeFree =>
      'Contame qué imaginás. Crear tu primera propuesta no tiene costo.';

  @override
  String get intakeVoiceTitle => 'Hablar con Kiu';

  @override
  String get intakeVoiceBody =>
      'Grabá un audio y contame qué vendés. Yo me encargo del resto.';

  @override
  String get intakeTextTitle => 'Escribir mi idea';

  @override
  String get intakeTextBody => 'Escribí una descripción de tu negocio.';

  @override
  String get intakeVoiceOff => 'Audio no disponible ahora';

  @override
  String get revealTitle => '¡POP! Tu tienda ya tomó forma.';

  @override
  String get revealBody =>
      'Kiu organizó tu negocio y preparó una tienda diseñada para vos.';

  @override
  String get revealExplore => 'Explorar mi tienda';

  @override
  String get revealAdjust => 'Hacer un ajuste';

  @override
  String get revealContinue => 'Continuar';

  @override
  String get adjustHint =>
      'Contale a Kiu qué querés cambiar: colores, nombres, precios…';

  @override
  String uploadSending(String name) {
    return 'Subiendo $name…';
  }

  @override
  String uploadCancel(String name) {
    return 'Cancelar subida de $name';
  }

  @override
  String get uploadRetry => 'Reintentar';

  @override
  String get uploadRemove => 'Quitar';

  @override
  String uploadCancelled(String name) {
    return '$name: subida cancelada.';
  }

  @override
  String fileTooManyTotal(String name, int mb) {
    return '$name: con este archivo superás los $mb MB por tienda.';
  }

  @override
  String get voiceNote => 'Nota de voz';

  @override
  String get paywallDemoNotice =>
      'Modo demostración. KiuPop todavía no procesa suscripciones ni cobros reales. Esta activación es simulada y no se cargará ningún monto.';

  @override
  String get paywallPlanName => 'Plan de demostración';

  @override
  String get paywallPriceNote =>
      'Precio de referencia para la demo. No se cobra.';

  @override
  String get paywallIncludedTitle => 'Incluido hoy';

  @override
  String get paywallBenefitCatalog => 'Catálogo público';

  @override
  String get paywallBenefitLinks => 'Enlaces compartibles';

  @override
  String get paywallBenefitCart => 'Carrito';

  @override
  String get paywallBenefitWhatsApp => 'Pedidos por WhatsApp';

  @override
  String get paywallBenefitAdmin => 'Administración de productos';

  @override
  String get paywallBenefitDesign => 'Personalización visual';

  @override
  String get paywallBenefitKiu => 'Asistencia de Kiu';

  @override
  String get paywallSoonTitle => 'Próximamente';

  @override
  String get paywallSoonPayments => 'Pagos en línea reales';

  @override
  String get paywallSoonIntegrations => 'Integraciones avanzadas';

  @override
  String get paywallSimulateCta => 'Simular activación';
}
