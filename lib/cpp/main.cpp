/****************************************************************************
 **
 ** Copyright (C) 2003-2006 Trolltech ASA. All rights reserved.
 **
 ** This file is part of a Qt Solutions component.
 **
 ** Licensees holding valid Qt Solutions licenses may use this file in
 ** accordance with the Qt Solutions License Agreement provided with the
 ** Software.
 **
 ** See http://www.trolltech.com/products/qt/addon/solutions/
 ** or email sales@trolltech.com for information about Qt Solutions
 ** License Agreements.
 **
 ** Contact info@trolltech.com if any conditions of this licensing are
 ** not clear to you.
 **
 ** This file is provided AS IS with NO WARRANTY OF ANY KIND, INCLUDING THE
 ** WARRANTY OF DESIGN, MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
 **
 ****************************************************************************/
#include <qapplication.h>
#include <stdlib.h>
#include <qfileinfo.h>

#include "sslserver.h"

/*
	 An SSL server that is started from the console.

	 This example demonstrates the use of the QtSSLSocket class in a
	 server application.
	 */
int main(int argc, char *argv[])
{
	QFileInfo cert("sslserver.pem");
	if (!cert.exists()) {
		qDebug("Note: This server requires the file sslserver.pem to exist, "
				"and to contain the SSL private key and certificate for "
				"this server, encoded in PEM format. Please read "
				"server.txt for more information.");
		return 1;
	}

	if (argc < 2) {
		qDebug("usage: %s <port>", argv[0]);
		qDebug("A simple SSL server.");
		return 1;
	}

	QApplication app(argc, argv, false);

	int port = atoi(argv[1]);

	SSLServer sserver(port);

	qDebug("Listening on port %i. Please press Ctrl-C to exit.", port);

	return app.exec();
}
