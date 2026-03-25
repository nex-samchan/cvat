# Copyright (C) 2021-2022 Intel Corporation
#
# SPDX-License-Identifier: MIT

from django.conf import settings
from django.contrib.auth.models import Group, User
from django.db.models.signals import post_migrate, post_save


def register_groups(sender, **kwargs):
    # Create all groups which corresponds system roles
    for role in settings.IAM_ROLES:
        Group.objects.get_or_create(name=role)


def _resolve_iap_role(email: str) -> str:
    """
    Walk IAM_IAP_ROLE_MAP top-to-bottom and return the first matching role.

    Supported patterns (evaluated in order):
      "user@example.com"  — exact email match
      "*@example.com"     — all addresses on a domain
      "*"                 — catch-all

    Returns IAM_DEFAULT_ROLE if no entry matches.
    """
    for pattern, role in getattr(settings, "IAM_IAP_ROLE_MAP", []):
        if pattern == email:
            return role
        if pattern.startswith("*@"):
            domain = pattern[2:]
            if email.split("@")[-1] == domain:
                return role
        if pattern == "*":
            return role
    return settings.IAM_DEFAULT_ROLE


if settings.IAM_TYPE == "BASIC":

    def create_user(sender, instance, created: bool, raw: bool, **kwargs):
        if created and raw:
            return

        from allauth.account import app_settings as allauth_settings
        from allauth.account.models import EmailAddress

        if instance.is_superuser and instance.is_staff:
            db_group = Group.objects.get(name=settings.IAM_ADMIN_ROLE)
            instance.groups.add(db_group)

            # create and verify EmailAddress for superuser accounts
            if allauth_settings.EMAIL_REQUIRED:
                EmailAddress.objects.get_or_create(
                    user=instance, email=instance.email, primary=True, verified=True
                )
        else:  # don't need to add default groups for superuser
            if created and not getattr(instance, "skip_group_assigning", None):
                db_group = Group.objects.get(name=settings.IAM_DEFAULT_ROLE)
                instance.groups.add(db_group)

elif settings.IAM_TYPE == "LDAP":

    def create_user(sender, user=None, ldap_user=None, **kwargs):
        user_groups = []
        for role in settings.IAM_ROLES:
            db_group = Group.objects.get(name=role)

            for ldap_group in settings.DJANGO_AUTH_LDAP_GROUPS[role]:
                if ldap_group.lower() in ldap_user.group_dns:
                    user_groups.append(db_group)
                    if role == settings.IAM_ADMIN_ROLE:
                        user.is_staff = user.is_superuser = True
                    break
        # add default group if no other group has been assigned
        if not len(user_groups):
            user_groups.append(Group.objects.get(name=settings.IAM_DEFAULT_ROLE))

        # It is important to save the user before adding groups. Please read
        # https://django-auth-ldap.readthedocs.io/en/latest/users.html#populating-users
        # The user instance will be saved automatically after the signal handler
        # is run.
        user.save()
        user.groups.set(user_groups)

elif settings.IAM_TYPE == "IAP":

    def create_user(sender, instance, created: bool, raw: bool, **kwargs):
        if not created or raw:
            return

        role = _resolve_iap_role(instance.email)
        db_group = Group.objects.get(name=role)
        instance.groups.add(db_group)

        if role == settings.IAM_ADMIN_ROLE:
            instance.is_staff = True
            instance.is_superuser = True
            instance.save(update_fields=["is_staff", "is_superuser"])


def register_signals(app_config):
    post_migrate.connect(register_groups, app_config, dispatch_uid=__name__ + ".register_groups")
    if settings.IAM_TYPE == "BASIC":
        # Add default groups and add admin rights to super users.
        post_save.connect(create_user, sender=User, dispatch_uid=__name__ + ".create_user")
    elif settings.IAM_TYPE == "LDAP":
        import django_auth_ldap.backend

        # Map groups from LDAP to roles, convert a user to super user if he/she
        # has an admin group.
        django_auth_ldap.backend.populate_user.connect(
            create_user, dispatch_uid=__name__ + ".create_user"
        )
    elif settings.IAM_TYPE == "IAP":
        # Assign role from IAM_IAP_ROLE_MAP whenever a new IAP user is created.
        post_save.connect(create_user, sender=User, dispatch_uid=__name__ + ".create_user")
