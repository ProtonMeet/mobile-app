/**
 * crypto-bridge.js
 * 
 * This file is used to demo what callback functions are needed to be implemented in the web app.
 */

window.cryptoBridge = {
    generateSRPProof: async (password, modulus, base64_server_ephemeral, base64_salt) => {
        // TODO: Implement SRP proof generation on web app.
    },
    computeKeyPassword: async (password, base64_salt) => {
        // TODO: Implement key password computation on web app.
    },
    decryptSessionKey: async (base64_key_packets, session_key_passphrase) => {
        // TODO: Implement session key decryption on web app.
    },
    decryptMessage: async (base64_key_packets, session_key_passphrase, base64_message) => {
        // TODO: Implement message decryption on web app.
    },
};

console.log('Crypto bridge initialized with Web Worker');