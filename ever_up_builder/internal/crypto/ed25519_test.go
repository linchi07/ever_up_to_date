package crypto

import (
	"crypto/ed25519"
	"encoding/base64"
	"testing"
)

func TestGenerateEd25519KeyPair(t *testing.T) {
	kp, err := GenerateEd25519KeyPair()
	if err != nil {
		t.Fatalf("GenerateEd25519KeyPair failed: %v", err)
	}

	if kp.PublicKey == "" || kp.PrivateKey == "" {
		t.Fatalf("expected non-empty keys, got pub=%q, priv=%q", kp.PublicKey, kp.PrivateKey)
	}

	pubBytes, err := base64.StdEncoding.DecodeString(kp.PublicKey)
	if err != nil {
		t.Fatalf("invalid public key base64: %v", err)
	}
	if len(pubBytes) != ed25519.PublicKeySize {
		t.Fatalf("expected pubkey size %d, got %d", ed25519.PublicKeySize, len(pubBytes))
	}

	privBytes, err := base64.StdEncoding.DecodeString(kp.PrivateKey)
	if err != nil {
		t.Fatalf("invalid private key base64: %v", err)
	}
	if len(privBytes) != ed25519.PrivateKeySize {
		t.Fatalf("expected privkey size %d, got %d", ed25519.PrivateKeySize, len(privBytes))
	}

	// Verify signing works
	message := []byte("everup-verification-test")
	sig := ed25519.Sign(privBytes, message)
	if !ed25519.Verify(pubBytes, message, sig) {
		t.Fatalf("signature verification failed")
	}
}
