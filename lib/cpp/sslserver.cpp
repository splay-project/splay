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
#include "sslserver.h"
#include <qdir.h>
#include <qfileinfo.h>
#include <qdatetime.h>

#include <qtsslsocket.h>

SSLServer::SSLServer(quint16 port, QObject *parent)
: QTcpServer(parent)
{
	listen(QHostAddress::Any, port);
}

void SSLServer::incomingConnection(int socket)
{
	// As soon as a client connects, pass its incoming socket id to a
	// SSLServerConnection child. This child is deleted after the
	// connection is closed (see the connectionClosed() slot).
	new SSLServerConnection(socket, this);
}

SSLServerConnection::SSLServerConnection(quint16 socketDescriptor,
		QObject *parent)
: QObject(parent)
{
	// Create an SSL socket and make its QTcpSocket use our accepted
	// socket, then give it the path to our certificate & private key
	// file. For notes on this file, please check the provided
	// "server.txt".
	socket = new QtSslSocket(QtSslSocket::Server, this);
	socket->socket()->setSocketDescriptor(socketDescriptor);
	socket->setPathToCertificate("sslserver.pem");
	socket->setPathToPrivateKey("sslserver.pem");

	// Notice the platform dependency here; the location of the CA
	// certificate bundle is specific to the OS.
	socket->setPathToCACertDir("/etc/ssl/certs");

	// Connect the SSL socket's signals to our slots.
	connect(socket, SIGNAL(connected()), SLOT(acceptedClient()));
	connect(socket, SIGNAL(disconnected()), SLOT(connectionClosed()));
	connect(socket, SIGNAL(readyRead()), SLOT(readData()));
	connect(socket, SIGNAL(error(QAbstractSocket::SocketError)), SLOT(error(QAbstractSocket::SocketError)));

	// Call sslAccepted(). After this, when the SSL socket emits
	// accepted(), we are ready to go. We ignore the return value of
	// this function, because it will always fail the first time we
	// call it.
	socket->sslAccept();
}

SSLServerConnection::~SSLServerConnection()
{
	// Report that the connection has closed.
	qDebug("Connection closed.");
}

void SSLServerConnection::acceptedClient()
{
	// Provide feedback to the user about incoming connections. This
	// slot is only called if the connection was established, so all
	// communication is now encrypted.
	qDebug("Accepted new client from %s:%d",
			qPrintable(socket->peerAddress().toString()),
			socket->peerPort());

	// Print a simple DOS-like prompt. Write this to the SSL socket.
	// The SSL socket encrypts the data, and sends it to the client.
	QString s = "Welcome to Fake-DOS 2.11\r\nC:\\>";
	socket->write(s.toLatin1().constData(), s.length());
}

void SSLServerConnection::readData()
{
	// First, read all incoming data from the client. The SSL socket
	// has already decrypted it for us. We assume that the client uses
	// a plain text protocol, so we convert the data to a QString.
	QString incoming(socket->readAll());

	// This server accepts only the commands "EXIT" and "DIR",
	// although case insensitive. All other commands are rejected with
	// "bad command or file name". Write response back to the client
	// through the SSL socket.
	QString command = incoming.toUpper().trimmed();
	if (command == "EXIT") {
		QString s = "system halted\r\n";
		socket->write(s.toLatin1().constData(), s.length());
		socket->close();
	} else if (command == "DIR") {
		QDir cwd(".");
		const QFileInfoList cwdlist = cwd.entryInfoList();
		if (cwdlist.isEmpty()) {
			QString s = "unable to list directory contents\r\nC:\\>";
			socket->write(s.toLatin1().constData(), s.length());
		} else {
			QString s = " Volume in drive C has no label.\r\n";
			s += " Volume Serial Number is C564-1226\r\n\r\n";
			s += " Directory of C:\\\r\n\r\n";
			QListIterator<QFileInfo> it(cwdlist);

			int nfiles = 0;
			int ndirs = 0;
			int tildes = 0;
			while (it.hasNext()) {
				QFileInfo f = it.next();
				QDate d = f.created().date();
				QTime t = f.created().time();
				QString line;

				bool dots = f.fileName() == "." || f.fileName() == "..";
				QString fname = dots ? QString("") : f.baseName().toUpper();
				QString lname = dots ? f.fileName() : f.completeSuffix().toUpper().left(3);

				if (fname.length() > 8) {
					QString tmp;
					tmp.sprintf("~%i", ++tildes);
					fname = fname.left(8 - tmp.length()) + tmp;
				}

				if (f.isDir()) {
					line.sprintf("%8s %3s <DIR>         %02i-%02i-%02i  %2i:%02i%c\r\n",
							qPrintable(fname), qPrintable(lname),
							d.day(), d.month(),
							(d.year() - 1900) % 100, t.hour() % 12, t.minute(),
							t.hour() > 12 ? 'p' : 'a');
				} else {
					line.sprintf("%8s %3s       %7d %02i-%02i-%02i  %2i:%02i%c\r\n",
							qPrintable(fname), qPrintable(lname),
							(int)f.size(), d.day(), d.month(),
							(d.year() - 1900) % 100, t.hour() % 12, t.minute(),
							t.hour() > 12 ? 'p' : 'a');
				}

				s += line;
				if (f.isDir())
					++ndirs;
				else
					++nfiles;
			}

			QString line;
			line.sprintf("%16i File(s)\r\n", nfiles);
			s += line;
			line.sprintf("%16i Dir(s)\r\n", ndirs);
			s += line;
			s += "C:\\>";
			socket->write(s.toLatin1().constData(), s.length());
		}

	} else {
		QString s = "bad command or file name\r\nC:\\>";
		socket->write(s.toLatin1().constData(), s.length());
	}
}

void SSLServerConnection::connectionClosed()
{
	// Although the socket may be closing, we must not delete it until
	// the delayed close is done.
	if (socket->socket()->state() == QAbstractSocket::ClosingState) {
		connect(socket->socket(), SIGNAL(disconnected()), SLOT(deleteLater()));
	} else {
		deleteLater();
		return;
	}

	qDebug("Connection closed.");
}

void SSLServerConnection::error(QAbstractSocket::SocketError)
{
	// The SSL socket conveniently provides human readable error
	// messages through the errorString() call. Note that sometimes
	// the errors come directly from the underlying SSL library, and
	// the quality of the text may vary.
	qDebug("Error: %s", qPrintable(socket->errorString()));
}
