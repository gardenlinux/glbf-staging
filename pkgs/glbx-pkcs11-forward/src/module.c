/*
 * A PKCS#11 provider module that holds no key and performs no cryptography.
 *
 * Loaded by an application (via OpenSSL's pkcs11 provider) that wants to sign
 * with a private key, this module presents exactly one token ("glbx") and one
 * key, and forwards every operation that needs the key — fetching the public
 * key, and signing a digest — to a signing service listening on a Unix socket.
 * The private key lives only in that service; it is never present here. The
 * socket to connect to is named by the GLBX_SIGN_SOCKET environment variable.
 *
 * Only the small subset of the Cryptoki interface an OpenSSL signing operation
 * actually calls is implemented; everything else returns
 * CKR_FUNCTION_NOT_SUPPORTED. The module reports the key's public attributes
 * (fetched from the service) so the consumer can build the key object, then
 * forwards the signing operation; the consumer assembles the final signature.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <p11-kit/pkcs11.h>
#include "sign.pb-c.h"

#define TOKEN_LABEL "glbx"
#define KEY_HANDLE 1
#define CERT_HANDLE 2
#define SESSION_HANDLE 1
#define SLOT_ID 0
#define MAX_MSG 65536
#define OBJECT_ID "glbx"

static char sock_path[108];
static Glbxsign__PublicKeyResponse *pubkey;  /* fetched from the service, cached */
static Glbxsign__CertResponse *cert;         /* fetched from the service, cached */

// Diagnostic logging, enabled by setting GLBX_SIGN_DEBUG. When its value is a
// path, logs are appended there (robust against interleaved build output);
// otherwise they go to stderr. Off by default so production builds stay quiet.
static FILE *debug_fp;
#define DBG(...) do { if (debug_fp) { fprintf(debug_fp, "[glbx-p11] " __VA_ARGS__); fputc('\n', debug_fp); fflush(debug_fp); } } while (0)

static void pad(CK_UTF8CHAR *dst, size_t n, const char *s)
{
	size_t l = strlen(s);
	memset(dst, ' ', n);
	memcpy(dst, s, l < n ? l : n);
}

/* One request/response exchange with the signing service over a fresh SEQPACKET socket. */
static Glbxsign__Envelope *exchange(const Glbxsign__Envelope *req)
{
	int fd = socket(AF_UNIX, SOCK_SEQPACKET, 0);
	if (fd < 0) { DBG("exchange: socket() failed"); return NULL; }

	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path) - 1);
	if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		DBG("exchange: connect(%s) failed: %s", sock_path, strerror(errno));
		close(fd);
		return NULL;
	}

	size_t len = glbxsign__envelope__get_packed_size(req);
	uint8_t *buf = malloc(len);
	glbxsign__envelope__pack(req, buf);
	ssize_t w = write(fd, buf, len);
	free(buf);
	if (w < 0) { DBG("exchange: write failed"); close(fd); return NULL; }

	uint8_t rbuf[MAX_MSG];
	ssize_t n = read(fd, rbuf, sizeof(rbuf));
	close(fd);
	if (n <= 0) { DBG("exchange: read returned %zd", n); return NULL; }

	return glbxsign__envelope__unpack(NULL, n, rbuf);
}

static CK_RV fetch_pubkey(void)
{
	if (pubkey) return CKR_OK;

	Glbxsign__PublicKeyRequest req = GLBXSIGN__PUBLIC_KEY_REQUEST__INIT;
	Glbxsign__Envelope env = GLBXSIGN__ENVELOPE__INIT;
	env.msg_case = GLBXSIGN__ENVELOPE__MSG_PUBLIC_KEY_REQUEST;
	env.public_key_request = &req;

	Glbxsign__Envelope *resp = exchange(&env);
	if (!resp || resp->msg_case != GLBXSIGN__ENVELOPE__MSG_PUBLIC_KEY_RESPONSE) {
		if (resp) glbxsign__envelope__free_unpacked(resp, NULL);
		return CKR_DEVICE_ERROR;
	}
	/* Take ownership of the response so it outlives the envelope free below. */
	pubkey = resp->public_key_response;
	resp->public_key_response = NULL;
	resp->msg_case = GLBXSIGN__ENVELOPE__MSG__NOT_SET;
	glbxsign__envelope__free_unpacked(resp, NULL);
	return CKR_OK;
}

static CK_RV fetch_cert(void)
{
	if (cert) return CKR_OK;

	Glbxsign__CertRequest req = GLBXSIGN__CERT_REQUEST__INIT;
	Glbxsign__Envelope env = GLBXSIGN__ENVELOPE__INIT;
	env.msg_case = GLBXSIGN__ENVELOPE__MSG_CERT_REQUEST;
	env.cert_request = &req;

	Glbxsign__Envelope *resp = exchange(&env);
	if (!resp || resp->msg_case != GLBXSIGN__ENVELOPE__MSG_CERT_RESPONSE) {
		DBG("fetch_cert: no cert response");
		if (resp) glbxsign__envelope__free_unpacked(resp, NULL);
		return CKR_DEVICE_ERROR;
	}
	/* Take ownership of the response so it outlives the envelope free below. */
	cert = resp->cert_response;
	resp->cert_response = NULL;
	resp->msg_case = GLBXSIGN__ENVELOPE__MSG__NOT_SET;
	glbxsign__envelope__free_unpacked(resp, NULL);
	DBG("fetch_cert: got %zu cert bytes", cert->der.len);
	return CKR_OK;
}

static CK_RV f_Initialize(CK_VOID_PTR p)
{
	const char *dbg = getenv("GLBX_SIGN_DEBUG");
	if (dbg) debug_fp = dbg[0] == '/' ? fopen(dbg, "ae") : stderr;
	const char *s = getenv("GLBX_SIGN_SOCKET");
	if (!s) { DBG("C_Initialize: GLBX_SIGN_SOCKET unset"); return CKR_DEVICE_ERROR; }
	strncpy(sock_path, s, sizeof(sock_path) - 1);
	DBG("C_Initialize: socket=%s", sock_path);
	return CKR_OK;
}

static CK_RV f_Finalize(CK_VOID_PTR p)
{
	if (pubkey) { glbxsign__public_key_response__free_unpacked(pubkey, NULL); pubkey = NULL; }
	if (cert) { glbxsign__cert_response__free_unpacked(cert, NULL); cert = NULL; }
	return CKR_OK;
}

static CK_RV f_GetInfo(CK_INFO_PTR info)
{
	memset(info, 0, sizeof(*info));
	info->cryptokiVersion.major = 3;
	pad(info->manufacturerID, sizeof(info->manufacturerID), "glbx");
	pad(info->libraryDescription, sizeof(info->libraryDescription), "glbx forwarder");
	return CKR_OK;
}

static CK_RV f_GetSlotList(CK_BBOOL present, CK_SLOT_ID_PTR list, CK_ULONG_PTR n)
{
	if (list) {
		if (*n < 1) return CKR_BUFFER_TOO_SMALL;
		list[0] = SLOT_ID;
	}
	*n = 1;
	return CKR_OK;
}

static CK_RV f_GetSlotInfo(CK_SLOT_ID slot, CK_SLOT_INFO_PTR info)
{
	memset(info, 0, sizeof(*info));
	pad(info->slotDescription, sizeof(info->slotDescription), "glbx slot");
	pad(info->manufacturerID, sizeof(info->manufacturerID), "glbx");
	info->flags = CKF_TOKEN_PRESENT;
	return CKR_OK;
}

static CK_RV f_GetTokenInfo(CK_SLOT_ID slot, CK_TOKEN_INFO_PTR info)
{
	memset(info, 0, sizeof(*info));
	pad(info->label, sizeof(info->label), TOKEN_LABEL);
	pad(info->manufacturerID, sizeof(info->manufacturerID), "glbx");
	pad(info->model, sizeof(info->model), "glbx");
	pad(info->serialNumber, sizeof(info->serialNumber), "0");
	info->flags = CKF_TOKEN_INITIALIZED;
	info->ulMaxSessionCount = CK_EFFECTIVELY_INFINITE;
	info->ulMaxRwSessionCount = CK_EFFECTIVELY_INFINITE;
	return CKR_OK;
}

static CK_RV f_GetMechanismList(CK_SLOT_ID slot, CK_MECHANISM_TYPE_PTR list, CK_ULONG_PTR n)
{
	if (fetch_pubkey() != CKR_OK) return CKR_DEVICE_ERROR;
	CK_MECHANISM_TYPE m = pubkey->key_case == GLBXSIGN__PUBLIC_KEY_RESPONSE__KEY_EC
			    ? CKM_ECDSA : CKM_RSA_PKCS;
	if (list) {
		if (*n < 1) return CKR_BUFFER_TOO_SMALL;
		list[0] = m;
	}
	*n = 1;
	return CKR_OK;
}

static CK_RV f_GetMechanismInfo(CK_SLOT_ID slot, CK_MECHANISM_TYPE type, CK_MECHANISM_INFO_PTR info)
{
	memset(info, 0, sizeof(*info));
	info->flags = CKF_SIGN;
	return CKR_OK;
}

static CK_RV f_OpenSession(CK_SLOT_ID slot, CK_FLAGS flags, CK_VOID_PTR app,
			   CK_NOTIFY notify, CK_SESSION_HANDLE_PTR session)
{
	*session = SESSION_HANDLE;
	return CKR_OK;
}

static CK_RV f_CloseSession(CK_SESSION_HANDLE session) { return CKR_OK; }

static CK_RV f_GetSessionInfo(CK_SESSION_HANDLE session, CK_SESSION_INFO_PTR info)
{
	memset(info, 0, sizeof(*info));
	info->slotID = SLOT_ID;
	info->state = CKS_RO_PUBLIC_SESSION;
	info->flags = CKF_SERIAL_SESSION;
	return CKR_OK;
}

static CK_RV f_Login(CK_SESSION_HANDLE s, CK_USER_TYPE t, CK_UTF8CHAR_PTR p, CK_ULONG l) { return CKR_OK; }
static CK_RV f_Logout(CK_SESSION_HANDLE s) { return CKR_OK; }

// find_class holds the CKA_CLASS the current search filters on, or NO_CLASS for
// an unfiltered search (which matches every object). find_pos walks the matching
// objects so each is returned exactly once.
#define NO_CLASS ((CK_OBJECT_CLASS)-1)
static CK_OBJECT_CLASS find_class;
static int find_pos;

static CK_RV f_FindObjectsInit(CK_SESSION_HANDLE s, CK_ATTRIBUTE_PTR tmpl, CK_ULONG n)
{
	find_class = NO_CLASS;
	find_pos = 0;
	for (CK_ULONG i = 0; i < n; i++) {
		if (tmpl[i].type == CKA_CLASS && tmpl[i].ulValueLen == sizeof(CK_OBJECT_CLASS))
			find_class = *(CK_OBJECT_CLASS *)tmpl[i].pValue;
	}
	DBG("C_FindObjectsInit: n_attrs=%lu class=0x%lx", n, (unsigned long)find_class);
	return CKR_OK;
}

static CK_RV f_FindObjects(CK_SESSION_HANDLE s, CK_OBJECT_HANDLE_PTR obj, CK_ULONG max, CK_ULONG_PTR n)
{
	// The token holds two objects: the private key and its certificate. Yield
	// those matching the search class (or all, when unfiltered), each once.
	static const struct { CK_OBJECT_HANDLE handle; CK_OBJECT_CLASS class; } objects[] = {
		{ KEY_HANDLE, CKO_PRIVATE_KEY },
		{ CERT_HANDLE, CKO_CERTIFICATE },
	};
	CK_ULONG count = 0;
	while (find_pos < 2 && count < max) {
		if (find_class == NO_CLASS || find_class == objects[find_pos].class)
			obj[count++] = objects[find_pos].handle;
		find_pos++;
	}
	*n = count;
	DBG("C_FindObjects: max=%lu returned=%lu", max, count);
	return CKR_OK;
}

static CK_RV f_FindObjectsFinal(CK_SESSION_HANDLE s) { return CKR_OK; }

static CK_RV serve(CK_ATTRIBUTE_PTR a, const void *val, CK_ULONG len)
{
	if (a->pValue) {
		if (a->ulValueLen < len) { a->ulValueLen = (CK_ULONG)-1; return CKR_BUFFER_TOO_SMALL; }
		memcpy(a->pValue, val, len);
	}
	a->ulValueLen = len;
	return CKR_OK;
}

static CK_RV cert_attribute(CK_ATTRIBUTE_PTR a)
{
	if (fetch_cert() != CKR_OK) return CKR_DEVICE_ERROR;
	switch (a->type) {
	case CKA_CLASS: { CK_OBJECT_CLASS c = CKO_CERTIFICATE; return serve(a, &c, sizeof(c)); }
	case CKA_CERTIFICATE_TYPE: { CK_CERTIFICATE_TYPE t = CKC_X_509; return serve(a, &t, sizeof(t)); }
	case CKA_VALUE: return serve(a, cert->der.data, cert->der.len);
	case CKA_TOKEN: { CK_BBOOL b = CK_TRUE; return serve(a, &b, sizeof(b)); }
	case CKA_PRIVATE: case CKA_MODIFIABLE: case CKA_COPYABLE: case CKA_DESTROYABLE:
		{ CK_BBOOL b = CK_FALSE; return serve(a, &b, sizeof(b)); }
	case CKA_ID: case CKA_LABEL: return serve(a, OBJECT_ID, sizeof(OBJECT_ID) - 1);
	// Other certificate attributes the consumer probes (subject, issuer, serial,
	// category, …) are optional; report them present-but-empty. The
	// unavailable-length sentinel would fail the consumer's batched fetch.
	default: a->ulValueLen = 0; return CKR_OK;
	}
}

static CK_RV key_attribute(CK_ATTRIBUTE_PTR a)
{
	if (fetch_pubkey() != CKR_OK) return CKR_DEVICE_ERROR;
	int is_ec = pubkey->key_case == GLBXSIGN__PUBLIC_KEY_RESPONSE__KEY_EC;
	switch (a->type) {
	case CKA_CLASS: { CK_OBJECT_CLASS c = CKO_PRIVATE_KEY; return serve(a, &c, sizeof(c)); }
	case CKA_KEY_TYPE: { CK_KEY_TYPE k = is_ec ? CKK_EC : CKK_RSA; return serve(a, &k, sizeof(k)); }
	case CKA_EC_PARAMS:
		if (is_ec) return serve(a, pubkey->ec->params.data, pubkey->ec->params.len);
		a->ulValueLen = (CK_ULONG)-1; return CKR_OK;
	case CKA_EC_POINT:
		if (is_ec) return serve(a, pubkey->ec->point.data, pubkey->ec->point.len);
		a->ulValueLen = (CK_ULONG)-1; return CKR_OK;
	case CKA_MODULUS:
		if (!is_ec) return serve(a, pubkey->rsa->modulus.data, pubkey->rsa->modulus.len);
		a->ulValueLen = (CK_ULONG)-1; return CKR_OK;
	case CKA_PUBLIC_EXPONENT:
		if (!is_ec) return serve(a, pubkey->rsa->exponent.data, pubkey->rsa->exponent.len);
		a->ulValueLen = (CK_ULONG)-1; return CKR_OK;
	case CKA_SIGN: case CKA_TOKEN: { CK_BBOOL b = CK_TRUE; return serve(a, &b, sizeof(b)); }
	case CKA_ALWAYS_AUTHENTICATE: case CKA_COPYABLE: case CKA_MODIFIABLE:
	case CKA_DESTROYABLE: case CKA_EXTRACTABLE: case CKA_PRIVATE:
		{ CK_BBOOL b = CK_FALSE; return serve(a, &b, sizeof(b)); }
	case CKA_ID: case CKA_LABEL: return serve(a, OBJECT_ID, sizeof(OBJECT_ID) - 1);
	default: a->ulValueLen = (CK_ULONG)-1; return CKR_OK;
	}
}

static CK_RV f_GetAttributeValue(CK_SESSION_HANDLE s, CK_OBJECT_HANDLE obj,
				 CK_ATTRIBUTE_PTR tmpl, CK_ULONG n)
{
	for (CK_ULONG i = 0; i < n; i++) {
		CK_RV rv = obj == CERT_HANDLE ? cert_attribute(&tmpl[i]) : key_attribute(&tmpl[i]);
		DBG("C_GetAttributeValue: obj=%lu attr=0x%lx -> rv=0x%lx len=%lu",
		    (unsigned long)obj, (unsigned long)tmpl[i].type, (unsigned long)rv,
		    (unsigned long)tmpl[i].ulValueLen);
		if (rv != CKR_OK) return rv;
	}
	return CKR_OK;
}

static CK_RV f_SignInit(CK_SESSION_HANDLE s, CK_MECHANISM_PTR m, CK_OBJECT_HANDLE key) { return CKR_OK; }

static CK_RV f_Sign(CK_SESSION_HANDLE s, CK_BYTE_PTR data, CK_ULONG dlen,
		    CK_BYTE_PTR sig, CK_ULONG_PTR slen)
{
	Glbxsign__SignRequest req = GLBXSIGN__SIGN_REQUEST__INIT;
	req.digest.data = data;
	req.digest.len = dlen;
	req.hash_algo = "sha256";
	Glbxsign__Envelope env = GLBXSIGN__ENVELOPE__INIT;
	env.msg_case = GLBXSIGN__ENVELOPE__MSG_SIGN_REQUEST;
	env.sign_request = &req;

	Glbxsign__Envelope *resp = exchange(&env);
	if (!resp || resp->msg_case != GLBXSIGN__ENVELOPE__MSG_SIGN_RESPONSE ||
	    resp->sign_response->signature.len == 0) {
		if (resp) glbxsign__envelope__free_unpacked(resp, NULL);
		return CKR_FUNCTION_FAILED;
	}

	Glbxsign__SignResponse *r = resp->sign_response;
	CK_RV rv = CKR_OK;
	if (!sig) {
		*slen = r->signature.len;
	} else if (*slen < r->signature.len) {
		rv = CKR_BUFFER_TOO_SMALL;
	} else {
		memcpy(sig, r->signature.data, r->signature.len);
		*slen = r->signature.len;
	}
	glbxsign__envelope__free_unpacked(resp, NULL);
	return rv;
}

static CK_RV f_GenerateRandom(CK_SESSION_HANDLE s, CK_BYTE_PTR buf, CK_ULONG len)
{
	memset(buf, 0x42, len);
	return CKR_OK;
}

static CK_FUNCTION_LIST function_list = {
	.version = { 3, 0 },
	.C_Initialize = f_Initialize,
	.C_Finalize = f_Finalize,
	.C_GetInfo = f_GetInfo,
	.C_GetFunctionList = C_GetFunctionList,
	.C_GetSlotList = f_GetSlotList,
	.C_GetSlotInfo = f_GetSlotInfo,
	.C_GetTokenInfo = f_GetTokenInfo,
	.C_GetMechanismList = f_GetMechanismList,
	.C_GetMechanismInfo = f_GetMechanismInfo,
	.C_OpenSession = f_OpenSession,
	.C_CloseSession = f_CloseSession,
	.C_GetSessionInfo = f_GetSessionInfo,
	.C_Login = f_Login,
	.C_Logout = f_Logout,
	.C_FindObjectsInit = f_FindObjectsInit,
	.C_FindObjects = f_FindObjects,
	.C_FindObjectsFinal = f_FindObjectsFinal,
	.C_GetAttributeValue = f_GetAttributeValue,
	.C_SignInit = f_SignInit,
	.C_Sign = f_Sign,
	.C_GenerateRandom = f_GenerateRandom,
};

CK_RV C_GetFunctionList(CK_FUNCTION_LIST_PTR_PTR out)
{
	*out = &function_list;
	return CKR_OK;
}
