package main

import (
        "fmt"
        "log"
        "net/http"
        "os"
        "strconv"
        "strings"
        "sync"
)

const counterFile = "/data/hits"

var mu sync.Mutex

func readCount() int {
        b, err := os.ReadFile(counterFile)
        if err != nil {
                return 0
        }
        n, _ := strconv.Atoi(strings.TrimSpace(string(b)))
        return n
}

func handler(w http.ResponseWriter, r *http.Request) {
        mu.Lock()
        defer mu.Unlock()

        n := readCount() + 1
        if err := os.WriteFile(counterFile, []byte(strconv.Itoa(n)), 0o644); err != nil {
                log.Printf("write failed: %v", err)
                http.Error(w, "could not persist counter", http.StatusInternalServerError)
                return
        }
        host, _ := os.Hostname()
        fmt.Fprintf(w, "Hello from %s! Hit count: %d\n", host, n)
}

func main() {
        http.HandleFunc("/", handler)
        log.Println("listening on :8080")
        log.Fatal(http.ListenAndServe(":8080", nil))
}
