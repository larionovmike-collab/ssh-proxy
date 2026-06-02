package main

import (
	"context"
	"flag"
	"log"
	"net"
	"sync"
    "time"
    "fmt"

	"github.com/armon/go-socks5"
	"golang.org/x/crypto/ssh"
)

// SSHDialer реализует интерфейс Dial для библиотеки SOCKS5
type SSHDialer struct {
	mu     sync.RWMutex
	client *ssh.Client
}

func (d *SSHDialer) SetClient(client *ssh.Client) {

	d.mu.Lock()
	defer d.mu.Unlock()

	old := d.client
	d.client = client

	if old != nil {
		old.Close()
	}
}

func (d *SSHDialer) GetClient() *ssh.Client {
	d.mu.RLock()
	defer d.mu.RUnlock()

	return d.client
}

func (d *SSHDialer) Dial(
	ctx context.Context,
	network,
	addr string,
) (net.Conn, error) {

	select {
	case <-ctx.Done():
		return nil, ctx.Err()

	default:

		client := d.GetClient()

		if client == nil {
			return nil, fmt.Errorf(
				"ssh disconnected",
			)
		}

		return client.Dial(
			network,
			addr,
		)
	}
}

func connectSSH(
	host string,
	config *ssh.ClientConfig,
) (*ssh.Client, error) {

	return ssh.Dial(
		"tcp",
		host,
		config,
	)
}

func isSSHAlive(
	client *ssh.Client,
) bool {

	conn, err := client.Dial(
		"tcp",
		"1.1.1.1:80",
	)

	if err != nil {
		return false
	}

	conn.Close()

	return true
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
	
	dialer := &SSHDialer{}
	dialer.SetClient(sshClient)
	
	go func() {
		for {
			time.Sleep(10 * time.Second)

			client := dialer.GetClient()

			if client == nil {
				continue
			}

			if isSSHAlive(client) {
				continue
			}

			log.Println("SSH disconnected. Reconnecting...")

			for {

				newClient, err := connectSSH(*sshHost, config)
				if err == nil {
					dialer.SetClient(newClient)

					log.Println("SSH reconnected")

					break
				}

				log.Printf("Reconnect failed: %v", err)

				time.Sleep(5 * time.Second)
			}
		}
	}()

	// 3. Настройка SOCKS5 сервера
	conf := &socks5.Config{
		Dial: dialer.Dial,
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
