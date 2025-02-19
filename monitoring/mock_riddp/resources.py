from monitoring.monitorlib import auth, infrastructure
from monitoring.mock_riddp import webapp
from . import config


utm_client = infrastructure.DSSTestSession(
  webapp.config.get(config.KEY_DSS_URL),
  auth.make_auth_adapter(webapp.config.get(config.KEY_AUTH_SPEC)))
