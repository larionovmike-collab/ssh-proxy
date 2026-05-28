package main

import (
	"context"
	"flag"
	"log"
	"net"

	"github.com/armon/go-socks5"
	"golang.org/x/crypto/ssh"
)

// SSHDialer реализует интерфейс Dial для библиотеки SOCKS5
type SSHDialer struct {
	client *ssh.Client
}

func (d *SSHDialer) Dial(ctx context.Context, network, addr string) (net.Conn, error) {
    // Можно использовать dialer с таймаутом из контекста, если нужно
    select {
    case <-ctx.Done():
        return nil, ctx.Err()
    default:
        return d.client.Dial(network, addr)
    }
}

func main() {
	// 1. Парсинг аргументов командной строки
	sshHost := flag.String("host", "", "SSH server host:port")
	sshUser := flag.String("user", "", "SSH username")
	sshPass := flag.String("pass", "", "SSH password")
	proxyPort := flag.String("port", "1080", "Local SOCKS5 port")
	flag.Parse()

	if *sshHost == "" || *sshUser == "" || *sshPass == "" {
		log.Fatal("Usage: go run main.go -host=server:22 -user=login -pass=password")
	}

	// 2. Настройка SSH клиента
	config := &ssh.ClientConfig{
		User: *sshUser,
		Auth: []ssh.AuthMethod{
			ssh.Password(*sshPass),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), // В продакшене лучше проверять ключи
	}

	log.Printf("Connecting to SSH server: %s...", *sshHost)
	sshClient, err := ssh.Dial("tcp", *sshHost, config)
	if err != nil {
		log.Fatalf("Failed to dial SSH: %v", err)
	}
	defer sshClient.Close()

	// 3. Настройка SOCKS5 сервера
	conf := &socks5.Config{
		Dial: (&SSHDialer{client: sshClient}).Dial,
	}
	server, err := socks5.New(conf)
	if err != nil {
		log.Fatalf("Failed to create SOCKS5 server: %v", err)
	}

	// 4. Запуск прослушивания
	addr := ":" + *proxyPort
	log.Printf("SOCKS5 proxy listening on %s", addr)
	if err := server.ListenAndServe("tcp", addr); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}