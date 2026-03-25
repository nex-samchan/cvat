# Copyright (C) 2021-2022 Intel Corporation
#
# SPDX-License-Identifier: MIT


import logging

from allauth.account import app_settings as allauth_settings
from allauth.account.models import EmailAddress
from django.conf import settings
from django.contrib.auth import get_user_model
from rest_framework import exceptions
from rest_framework.authentication import BasicAuthentication, BaseAuthentication

logger = logging.getLogger(__name__)
User = get_user_model()


class BasicAuthenticationEx(BasicAuthentication):
    def authenticate(self, request):
        result = super().authenticate(request)

        if (
            allauth_settings.EMAIL_VERIFICATION
            == allauth_settings.EmailVerificationMethod.MANDATORY
            and result
        ):
            user = result[0]
            if not EmailAddress.objects.is_verified(user.email):
                raise exceptions.AuthenticationFailed("E-mail is not verified.")

        return result


class IAPAuthentication(BaseAuthentication):
    """
    DRF authentication class for GCP Identity-Aware Proxy.

    Verifies the signed JWT in the X-Goog-Iap-Jwt-Assertion header using
    Google's public keys and the configured IAM_IAP_AUDIENCE. On success,
    finds or creates a Django user whose username equals the verified email.
    The verified JWT claims dict is stored on request.auth for downstream use.
    """

    IAP_HEADER = "HTTP_X_GOOG_IAP_JWT_ASSERTION"

    def authenticate(self, request):
        token = request.META.get(self.IAP_HEADER)
        if not token:
            return None

        claims = self._verify_iap_jwt(token)
        email = claims.get("email", "")
        if not email:
            raise exceptions.AuthenticationFailed("IAP JWT contains no email claim.")

        user = self._get_or_create_user(email)
        return (user, claims)

    def authenticate_header(self, request):
        return "IAP"

    @staticmethod
    def _verify_iap_jwt(token: str) -> dict:
        """Verify the IAP-signed JWT and return its claims."""
        try:
            import google.auth.transport.requests
            import google.oauth2.id_token

            http_request = google.auth.transport.requests.Request()
            audience = settings.IAM_IAP_AUDIENCE
            if not audience:
                raise exceptions.AuthenticationFailed(
                    "IAM_IAP_AUDIENCE is not configured. "
                    "Set it to the full IAP backend service path."
                )
            claims = google.oauth2.id_token.verify_token(
                token,
                http_request,
                audience=audience,
            )
        except Exception as exc:
            logger.warning("IAP JWT verification failed: %s", exc)
            raise exceptions.AuthenticationFailed(
                f"IAP JWT verification failed: {exc}"
            ) from exc

        return claims

    @staticmethod
    def _get_or_create_user(email: str):
        """Return the Django user for this email, creating one if needed."""
        user, created = User.objects.get_or_create(
            username=email,
            defaults={"email": email},
        )
        if created:
            # post_save signal in signals.py assigns the correct group
            logger.info("Created new IAP user: %s", email)
        return user


class IAPBackend:
    """
    Django authentication backend for IAP.

    Used by IAPLoginView to establish a Django session after JWT verification.
    Per-request authentication is handled by IAPAuthentication (DRF class above).
    """

    def authenticate(self, request, iap_claims=None):
        if iap_claims is None:
            return None
        email = iap_claims.get("email", "")
        if not email:
            return None
        user, _ = User.objects.get_or_create(
            username=email,
            defaults={"email": email},
        )
        return user

    def get_user(self, user_id):
        try:
            return User.objects.get(pk=user_id)
        except User.DoesNotExist:
            return None
