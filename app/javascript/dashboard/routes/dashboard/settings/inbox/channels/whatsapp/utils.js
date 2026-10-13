import { loadScript } from 'dashboard/helper/DOMHelpers';

export const loadFacebookSdk = async () => {
  return loadScript('https://connect.facebook.net/en_US/sdk.js', {
    async: true,
    defer: true,
    crossOrigin: 'anonymous',
  });
};

export const initializeFacebook = (appId, apiVersion) => {
  const version = apiVersion || 'v22.0';
  return new Promise(resolve => {
    const init = () => {
      window.FB.init({
        appId,
        autoLogAppEvents: true,
        xfbml: true,
        version,
      });
      resolve();
    };

    if (window.FB) {
      init();
    } else {
      window.fbAsyncInit = init;
    }
  });
};

// Only waba_id is guaranteed: Meta's coexistence FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING
// event documents data: { waba_id } alone — no business_id or phone_number_id.
export const isValidBusinessData = businessData => {
  return Boolean(businessData && businessData.waba_id);
};

const COEXISTENCE_FINISH_EVENT = 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING';

const FINISH_EVENTS = ['FINISH', COEXISTENCE_FINISH_EVENT];

// Terminal events that end the flow without a Cloud API phone number we can build an
// inbox from. Embedded Signup v4 can emit any of them depending on the products
// enabled on the configuration; without an explicit branch the popup simply closes
// and the caller waits on a promise that never settles.
const UNSUPPORTED_FINISH_EVENTS = [
  'FINISH_ONLY_WABA',
  'FINISH_OBO_MIGRATION',
  'FINISH_GRANT_ONLY_API_ACCESS',
];

export const SIGNUP_RESULT = Object.freeze({
  FINISH: 'finish',
  UNSUPPORTED: 'unsupported',
  CANCEL: 'cancel',
  ERROR: 'error',
  IGNORE: 'ignore',
});

// Maps a WA_EMBEDDED_SIGNUP payload onto the outcomes callers act on. v4 spells the
// explicit failure event `ERROR` where v3 used `error`, and also reports user-facing
// failures as a CANCEL carrying an error_message — a bare CANCEL is a deliberate
// dismissal, so the two have to be told apart rather than both read as "cancelled".
export const classifySignupEvent = data => {
  const event = data?.event;
  if (typeof event !== 'string') return { type: SIGNUP_RESULT.IGNORE };

  const errorMessage = data?.error_message;

  if (FINISH_EVENTS.includes(event)) {
    return {
      type: SIGNUP_RESULT.FINISH,
      isCoexistence: event === COEXISTENCE_FINISH_EVENT,
    };
  }

  if (UNSUPPORTED_FINISH_EVENTS.includes(event)) {
    return { type: SIGNUP_RESULT.UNSUPPORTED };
  }

  if (event.toUpperCase() === 'ERROR') {
    return { type: SIGNUP_RESULT.ERROR, errorMessage };
  }

  if (event === 'CANCEL') {
    return errorMessage
      ? { type: SIGNUP_RESULT.ERROR, errorMessage }
      : { type: SIGNUP_RESULT.CANCEL };
  }

  return { type: SIGNUP_RESULT.IGNORE };
};

const isFacebookOrigin = origin => {
  try {
    const { hostname } = new URL(origin);
    return hostname === 'facebook.com' || hostname.endsWith('.facebook.com');
  } catch {
    return false;
  }
};

const parseMessageData = rawData => {
  if (typeof rawData === 'string') {
    try {
      return JSON.parse(rawData);
    } catch {
      return null;
    }
  }

  if (typeof rawData === 'object' && rawData !== null) {
    return rawData;
  }

  return null;
};

const unwrapEmbeddedSignupPayload = data => {
  if (data?.type === 'WA_EMBEDDED_SIGNUP') return data;

  // Meta has changed the envelope used by some Facebook Login for Business
  // responses over time. Accept one extra wrapper without relaxing the origin
  // check or logging the sensitive payload itself.
  if (data?.data?.type === 'WA_EMBEDDED_SIGNUP') return data.data;

  return null;
};

export const createMessageHandler = onEmbeddedSignupData => {
  return event => {
    if (!isFacebookOrigin(event.origin)) return;

    const data = parseMessageData(event.data);
    if (!data) return;

    const embeddedPayload = unwrapEmbeddedSignupPayload(data);

    // Deliberately log metadata only. Never log auth codes, tokens, phone
    // numbers, WABA ids, or the raw payload.
    console.info('[WhatsApp Embedded Signup] Meta message received', {
      origin: event.origin,
      type: embeddedPayload?.type || data?.type || 'unknown',
      event: embeddedPayload?.event || data?.event || 'unknown',
      hasEmbeddedPayload: Boolean(embeddedPayload),
      hasBusinessData: Boolean(embeddedPayload?.data),
    });

    if (embeddedPayload) {
      onEmbeddedSignupData(embeddedPayload);
    }
  };
};

export const initWhatsAppEmbeddedSignup = configId => {
  return new Promise((resolve, reject) => {
    window.FB.login(
      response => {
        const hasCode = Boolean(response?.authResponse?.code);

        // Keep this diagnostic intentionally free of credentials.
        console.info('[WhatsApp Embedded Signup] FB.login completed', {
          status: response?.status || 'unknown',
          hasAuthResponse: Boolean(response?.authResponse),
          hasCode,
          hasError: Boolean(response?.error),
        });

        if (hasCode) {
          resolve(response.authResponse.code);
        } else if (response?.error) {
          reject(new Error(response.error));
        } else {
          reject(new Error('Login cancelled'));
        }
      },
      {
        config_id: configId,
        response_type: 'code',
        override_default_response_type: true,
        extras: {
          setup: {},
          featureType: 'whatsapp_business_app_onboarding',
          sessionInfoVersion: '3',
        },
      }
    );
  });
};

export const setupFacebookSdk = async (appId, apiVersion) => {
  const version = apiVersion || 'v22.0';
  await loadFacebookSdk();
  await initializeFacebook(appId, version);
};
