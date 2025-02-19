import sys

from monitoring.rid_qualifier.host import webapp
from . import config


def main(argv):
  del argv
  webapp.run(host='localhost', port=webapp.config.get(config.KEY_RID_QUALIFIER_HOST_PORT))


if __name__ == '__main__':
  main(sys.argv)
