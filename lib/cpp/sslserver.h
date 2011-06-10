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

#ifndef SSLSERVER_H
#define SSLSERVER_H
#include <QtNetwork>

class QtSslSocket;

class SSLServerConnection : public QObject
{
	Q_OBJECT

 public:
	SSLServerConnection(quint16 socket, QObject *parent = 0);
	~SSLServerConnection();

	public slots:
	void acceptedClient();
	void readData();
	void connectionClosed();
	void error(QAbstractSocket::SocketError err);

 private:
	unsigned int readBytes;
	unsigned int writtenBytes;

	QtSslSocket *socket;
};

class SSLServer : public QTcpServer
{
	Q_OBJECT

 public:
	SSLServer(quint16 port, QObject *parent = 0);

	void incomingConnection(int socket);
};

#endif
