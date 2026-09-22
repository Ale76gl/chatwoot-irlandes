import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  setupFacebookSdk,
  initWhatsAppEmbeddedSignup,
  createMessageHandler,
  isValidBusinessData,
  classifySignupEvent,
  SIGNUP_RESULT,
} from 'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils';

const INCOMPLETE_SIGNUP_TIMEOUT_MS = 20000;

// Drives Meta's WhatsApp embedded-signup popup (Facebook JS SDK). FB.login()
// resolves an auth `code` while the WABA identifiers (waba_id, phone_number_id)
// arrive separately over a postMessage event — order isn't guaranteed, so we
// hold both and resolve once both are present.
//
// `runEmbeddedSignup` returns the signup credentials; the caller exchanges them
// for an inbox via `inboxes/createWhatsAppEmbeddedSignup` and owns its own UX
// (alerts, navigation, etc). Resolves `null` when the user cancels the popup;
// rejects on SDK load errors, signup errors, and completions that yield no usable
// phone number. The window listener is scoped to a single run, so this is safe to
// call from anywhere without lifecycle wiring.
export function useWhatsappEmbeddedSignup() {
  const { t } = useI18n();
  const isAuthenticating = ref(false);

  const runEmbeddedSignup = () => {
    if (isAuthenticating.value) return Promise.resolve(null);
    isAuthenticating.value = true;

    return new Promise((resolve, reject) => {
      let authCode = null;
      let businessData = null;
      let isCoexistence = false;
      let settled = false;
      let messageHandler;
      let incompleteSignupTimer = null;

      const clearIncompleteTimer = () => {
        if (incompleteSignupTimer) {
          window.clearTimeout(incompleteSignupTimer);
          incompleteSignupTimer = null;
        }
      };

      const settle = (fn, value) => {
        if (settled) return;
        settled = true;
        clearIncompleteTimer();
        window.removeEventListener('message', messageHandler);
        isAuthenticating.value = false;
        fn(value);
      };

      const rejectIncompleteSignup = () => {
        console.warn('[WhatsApp Embedded Signup] Incomplete completion', {
          hasAuthCode: Boolean(authCode),
          hasBusinessData: Boolean(businessData),
        });

        settle(
          reject,
          new Error(
            'Meta completed the login but did not return the WhatsApp Embedded Signup data. Verify that the Configuration ID was created for WhatsApp Embedded Signup and try again.'
          )
        );
      };

      // Start a short grace period only after one half of the completion has
      // arrived. This avoids timing out while the user is still working inside
      // Meta's popup, but prevents an infinite spinner when Meta returns only an
      // OAuth code (for example when a non-Embedded-Signup configuration is used).
      const armIncompleteTimer = () => {
        if (settled || incompleteSignupTimer || (authCode && businessData)) return;
        incompleteSignupTimer = window.setTimeout(
          rejectIncompleteSignup,
          INCOMPLETE_SIGNUP_TIMEOUT_MS
        );
      };

      // Both the auth code and the business data arrive asynchronously and in
      // no fixed order; only resolve once we're holding both.
      const resolveIfReady = () => {
        console.info('[WhatsApp Embedded Signup] Completion state', {
          hasAuthCode: Boolean(authCode),
          hasBusinessData: Boolean(businessData),
          isCoexistence,
        });

        if (!authCode || !businessData) {
          armIncompleteTimer();
          return;
        }

        settle(resolve, {
          code: authCode,
          business_id: businessData.business_id || '',
          waba_id: businessData.waba_id,
          phone_number_id: businessData.phone_number_id || '',
          is_coexistence: isCoexistence,
        });
      };

      messageHandler = createMessageHandler(data => {
        const result = classifySignupEvent(data);

        console.info('[WhatsApp Embedded Signup] Classified Meta event', {
          result: result.type,
          event: data?.event || 'unknown',
          hasBusinessData: Boolean(data?.data),
        });

        if (result.type === SIGNUP_RESULT.FINISH) {
          // Keep the first terminal event: a coexistence FINISH must win over a
          // later normal FINISH that can arrive before the auth code is known.
          if (businessData) return;
          if (!isValidBusinessData(data.data)) {
            const invalidData = t(
              'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.INVALID_BUSINESS_DATA'
            );
            settle(reject, new Error(invalidData));
            return;
          }
          businessData = data.data;
          isCoexistence = result.isCoexistence;
          resolveIfReady();
        } else if (result.type === SIGNUP_RESULT.UNSUPPORTED) {
          const unsupported = t(
            'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.UNSUPPORTED_COMPLETION'
          );
          settle(reject, new Error(unsupported));
        } else if (result.type === SIGNUP_RESULT.CANCEL) {
          settle(resolve, null);
        } else if (result.type === SIGNUP_RESULT.ERROR) {
          const signupError = t(
            'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SIGNUP_ERROR'
          );
          settle(reject, new Error(result.errorMessage || signupError));
        }
      });

      window.addEventListener('message', messageHandler);

      (async () => {
        try {
          console.info('[WhatsApp Embedded Signup] Initializing Meta SDK', {
            hasAppId: Boolean(window.chatwootConfig?.whatsappAppId),
            hasConfigurationId: Boolean(
              window.chatwootConfig?.whatsappConfigurationId
            ),
            apiVersion:
              window.chatwootConfig?.whatsappApiVersion || 'default',
          });

          await setupFacebookSdk(
            window.chatwootConfig?.whatsappAppId,
            window.chatwootConfig?.whatsappApiVersion
          );
          authCode = await initWhatsAppEmbeddedSignup(
            window.chatwootConfig?.whatsappConfigurationId
          );
          resolveIfReady();
        } catch (error) {
          // FB.login() rejects with 'Login cancelled' when the user dismisses
          // the popup — treat it as a cancel rather than an error.
          if (error.message === 'Login cancelled') {
            settle(resolve, null);
          } else {
            settle(reject, error);
          }
        }
      })();
    });
  };

  return { isAuthenticating, runEmbeddedSignup };
}
