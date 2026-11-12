# ha_bridge_pro.py -- runtime license-gate bypass for HA Bridge 0.8.6 (PyArmor "basic" protected build)
# Loaded through a site-packages .pth hook. It never touches the PyArmor ciphertext in /app/backend.
# Effect: LicenseService reports ACTIVE / pro edition, allows() always True, all online checks are
# local no-ops, and the separate Pro entitlement gate module.3d_interaction (own verifier path,
# not routed through LicenseService.allows) is forced open too.
import sys, os, datetime

TARGET = "backend.app.license.service"
TARGET_3D = "backend.app.modules.interaction3d.access"
_APP_ROOT = os.environ.get("APP_ROOT", "/app")
_LOG = os.environ.get("HA_BRIDGE_PRO_LOG", "/data/cr-license-calls.log")

_EXTRA_FEATURES = (
    "ui.base", "api", "assets", "editor", "display", "ha.sync", "ha.control",
    "ha.configure", "projects.write", "runtime.websocket",
    "interaction3d", "uiPack", "studio3d", "modules.interaction3d",
    "module.3d_interaction",
)


def _log(msg):
    try:
        with open(_LOG, "a", encoding="utf-8") as fh:
            fh.write("%s %s\n" % (datetime.datetime.now().isoformat(timespec="seconds"), msg))
    except Exception:
        pass


def _iso(dt):
    return dt.isoformat().replace("+00:00", "Z")


def _status_payload(self):
    now = datetime.datetime.now(datetime.timezone.utc)
    far = now + datetime.timedelta(days=3650)
    feats = []
    try:
        base = getattr(sys.modules.get(TARGET), "BASE_FEATURES", ())
        feats = sorted(set(base) | set(_EXTRA_FEATURES))
    except Exception:
        feats = sorted(set(_EXTRA_FEATURES))
    try:
        instance_id = self._instance_id()
    except Exception:
        instance_id = None
    return {
        "required": True,
        "allowed": True,
        "status": "ACTIVE",
        "edition": "pro",
        "features": feats,
        "editorAllowed": True,
        "featureAccess": {"editor": True, "interaction3d": True, "uiPack": True},
        "leaseExpiresAt": _iso(far),
        "activatedAt": _iso(now),
        "activationCodeId": "CR-PRO-UNLOCK",
        "leaseId": "cr-local-lease",
        "instanceId": instance_id,
        "maxProjects": -1,
        "maxDisplays": -1,
        "errorCode": None,
        "retryable": False,
        "canRetry": False,
        "retrying": False,
        "retryAttempt": 0,
        "nextRetryAt": None,
    }


def _availability_payload(self):
    p = _status_payload(self)
    return {
        "status": "ACTIVE",
        "errorCode": None,
        "retryable": False,
        "canRetry": False,
        "retrying": False,
        "retryAttempt": 0,
        "nextRetryAt": None,
        "displayAllowed": True,
        "allowed": True,
        "edition": "pro",
        "editorAllowed": True,
        "features": p["features"],
        "featureAccess": p["featureAccess"],
        "leaseExpiresAt": p["leaseExpiresAt"],
    }


def _apply(mod):
    ls = mod.LicenseService

    def allows(self, feature=None, *, database=None):
        _log("allows(feature=%r) -> True" % (feature,))
        return True

    async def _async_payload(self, *a, **kw):
        await _asyncio_sleep0()
        return _status_payload(self)

    async def _async_noop(self, *a, **kw):
        await _asyncio_sleep0()
        return None

    def _noop(self, *a, **kw):
        return None

    def _passthrough(self, state, *a, **kw):
        return state

    ls.allows = allows
    ls._verified_access = lambda self, *a, **kw: True
    ls.status = _status_payload
    ls.availability = _availability_payload
    ls.activate = _async_payload
    ls.heartbeat = _async_payload
    ls.recover = _async_payload
    ls.retry_now = _async_payload
    ls.start = _async_noop
    ls.stop = _async_noop
    ls._heartbeat_wait_seconds = lambda self, *a, **kw: 300
    ls._scheduled_wait_seconds = lambda self, *a, **kw: 300
    ls._validate_saved_state = _passthrough
    ls._mark_failure = _noop
    ls._mark_revoked = _noop
    _log("PATCH: LicenseService patched on %s" % mod.__name__)


async def _asyncio_sleep0():
    import asyncio
    await asyncio.sleep(0)


# ---------------------------------------------------------------------------
# Pro entitlement gate: backend.app.modules.interaction3d.access
#   allowed(request, *, database=None) -> bool
#   require_access(request, *, database=None) -> None    (raises 403)
#   access_grant(request) -> dict                       (verifies signed lease, 403 on failure)
#   require_document_changes(request, document, previous=None, *, database=None) -> None
# ---------------------------------------------------------------------------
def _apply_3d(mod):
    def allowed(request, *, database=None):
        _log("interaction3d.allowed() -> True")
        return True

    def require_access(request, *, database=None):
        _log("interaction3d.require_access() -> open")
        return None

    def access_grant(request):
        try:
            max_lifetime = float(getattr(mod, "MAX_GRANT_SECONDS", 60))
        except Exception:
            max_lifetime = 60.0
        _log("interaction3d.access_grant() -> synthetic grant")
        return {
            "allowed": True,
            "feature": getattr(mod, "FEATURE", "module.3d_interaction"),
            "phase": "authorization-shell",
            "validForSeconds": max_lifetime,
            "expiresAt": _iso(datetime.datetime.now(datetime.timezone.utc)
                              + datetime.timedelta(seconds=max_lifetime)),
            "entitlements": [getattr(mod, "FEATURE", "module.3d_interaction")],
            "code": None,
        }

    def require_document_changes(request, document, previous=None, *, database=None):
        _log("interaction3d.require_document_changes() -> open")
        return None

    mod.allowed = allowed
    mod.require_access = require_access
    mod.access_grant = access_grant
    mod.require_document_changes = require_document_changes
    _log("PATCH: interaction3d gate patched on %s" % mod.__name__)


def _patch_module(name, mod):
    if name == TARGET:
        _apply(mod)
    elif name == TARGET_3D:
        _apply_3d(mod)


class _PatchFinder:
    """MetaPathFinder hooking exactly the two guard modules, then unhooking itself."""

    _names = (TARGET, TARGET_3D)

    def __init__(self):
        self._seen = set()

    def find_spec(self, fullname, path=None, target=None):
        if fullname not in self._names:
            return None
        if fullname in self._seen:
            return None
        self._seen.add(fullname)
        try:
            for finder in list(sys.meta_path):
                if finder is self:
                    continue
                find = getattr(finder, "find_spec", None)
                if find is None:
                    continue
                spec = find(fullname, path, target)
                if spec is not None and spec.loader is not None:
                    spec.loader = _LoaderProxy(spec.loader, fullname)
                    break
            else:
                return None
        except Exception as exc:
            _log("HOOK-ERROR %s: %r" % (fullname, exc))
            return None
        if len(self._seen) >= len(self._names):
            try:
                sys.meta_path.remove(self)
            except ValueError:
                pass
        _log("HOOK-ARMED for %s" % fullname)
        return spec


class _LoaderProxy:
    def __init__(self, inner, fullname):
        self._inner = inner
        self._fullname = fullname

    def __getattr__(self, item):
        return getattr(self._inner, item)

    def create_module(self, spec):
        create = getattr(self._inner, "create_module", None)
        if create is not None:
            return create(spec)
        return None

    def exec_module(self, module):
        self._inner.exec_module(module)
        try:
            _patch_module(self._fullname, module)
        except Exception as exc:
            _log("PATCH-ERROR %s: %r" % (self._fullname, exc))


def install():
    for name in _PatchFinder._names:
        if name in sys.modules:
            try:
                _patch_module(name, sys.modules[name])
            except Exception as exc:
                _log("EARLY-PATCH-ERROR %s: %r" % (name, exc))
    sys.meta_path.insert(0, _PatchFinder())


install()
