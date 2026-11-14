package android.security.keystore;

import java.nio.ByteBuffer;
import java.security.*;
import java.security.spec.AlgorithmParameterSpec;
import javax.crypto.*;

/**
 * Shared operation authorization for the two supported software cipher routes.
 *
 * Instamac F1c: Android's Cipher contract allows a NULL input to
 * engineDoFinal/engineUpdate -- the no-argument Cipher.doFinal() path in
 * CipherInputStream passes (null, 0, 0). Forwarding that null straight to the
 * JDK's own Cipher throws IllegalArgumentException("Bad arguments"), which
 * Instagram turns into a fatal dex error (System.exit(10)) the moment it
 * decrypts anything persisted -- i.e. on every boot with existing data.
 * Normalize null to an empty array; that is what the platform providers do.
 */
abstract class AndroidKeyStoreCipherSpi extends CipherSpi {
    private static final byte[] NO_INPUT = new byte[0];
    private static byte[] inputOrEmpty(byte[] input) { return input == null ? NO_INPUT : input; }
    protected Cipher delegate;
    protected AndroidKeyStoreAuthPolicy policy = AndroidKeyStoreAuthPolicy.NONE;
    protected AndroidKeyStoreProtectedKey handle;
    private boolean authorized;
    protected abstract Cipher create() throws InvalidKeyException;
    protected abstract Key prepare(Key key, int operation) throws InvalidKeyException;
    protected void validateParameters(AlgorithmParameterSpec parameters) throws InvalidKeyException { }
    protected void validateParameters(AlgorithmParameters parameters) throws InvalidKeyException { }
    private Key begin(Key key, int operation) throws InvalidKeyException {
        delegate = null; handle = null; policy = AndroidKeyStoreAuthPolicy.NONE; authorized = false;
        Key internal = prepare(key, operation);
        policy.begin(this); policy.checkAtInitialization(this);
        delegate = create(); return internal;
    }
    @Override protected final void engineInit(int operation, Key key, SecureRandom random) throws InvalidKeyException {
        Key internal = begin(key, operation); validateParameters((AlgorithmParameterSpec)null); delegate.init(operation, internal, random);
    }
    @Override protected final void engineInit(int operation, Key key, AlgorithmParameterSpec parameters, SecureRandom random)
            throws InvalidKeyException, InvalidAlgorithmParameterException {
        Key internal = begin(key, operation); validateParameters(parameters); delegate.init(operation, internal, parameters, random);
    }
    @Override protected final void engineInit(int operation, Key key, AlgorithmParameters parameters, SecureRandom random)
            throws InvalidKeyException, InvalidAlgorithmParameterException {
        Key internal = begin(key, operation); validateParameters(parameters); delegate.init(operation, internal, parameters, random);
    }
    private void authorize() throws InvalidKeyException {
        if (handle != null) MacApkKeyStoreBackend.get().checkGeneration(handle.alias(), handle.generation());
        if (!authorized) { policy.check(this); authorized = true; }
    }
    private void updateAuthorization() {
        try { authorize(); }
        catch (InvalidKeyException denied) { throw new ProviderException("Keystore operation is not authorized", denied); }
    }
    private void finalAuthorization() throws IllegalBlockSizeException {
        try { authorize(); }
        catch (InvalidKeyException denied) {
            IllegalBlockSizeException failure = new IllegalBlockSizeException("Keystore operation is not authorized");
            failure.initCause(denied); throw failure;
        }
    }
    private void finished() { authorized = false; policy.begin(this); }
    @Override protected final int engineGetOutputSize(int size) { return delegate.getOutputSize(size); }
    @Override protected final byte[] engineGetIV() { return delegate == null ? null : delegate.getIV(); }
    @Override protected final AlgorithmParameters engineGetParameters() { return delegate == null ? null : delegate.getParameters(); }
    @Override protected final byte[] engineUpdate(byte[] input, int offset, int length) {
        updateAuthorization(); return delegate.update(inputOrEmpty(input), offset, length);
    }
    @Override protected final int engineUpdate(byte[] input, int offset, int length, byte[] output, int outputOffset) throws ShortBufferException {
        updateAuthorization(); return delegate.update(inputOrEmpty(input), offset, length, output, outputOffset);
    }
    @Override protected final void engineUpdateAAD(byte[] input, int offset, int length) {
        if (input == null) return;
        delegate.updateAAD(input, offset, length);
    }
    @Override protected final void engineUpdateAAD(ByteBuffer input) {
        if (input == null) return;
        delegate.updateAAD(input);
    }
    @Override protected final byte[] engineDoFinal(byte[] input, int offset, int length) throws IllegalBlockSizeException, BadPaddingException {
        try { finalAuthorization(); return delegate.doFinal(inputOrEmpty(input), offset, length); } finally { finished(); }
    }
    @Override protected final int engineDoFinal(byte[] input, int offset, int length, byte[] output, int outputOffset)
            throws ShortBufferException, IllegalBlockSizeException, BadPaddingException {
        try { finalAuthorization(); return delegate.doFinal(inputOrEmpty(input), offset, length, output, outputOffset); } finally { finished(); }
    }
    @Override protected final byte[] engineWrap(Key key) throws IllegalBlockSizeException, InvalidKeyException {
        try { authorize(); return delegate.wrap(key); } finally { finished(); }
    }
    @Override protected final Key engineUnwrap(byte[] key, String algorithm, int type) throws InvalidKeyException, NoSuchAlgorithmException {
        try { authorize(); return delegate.unwrap(key, algorithm, type); } finally { finished(); }
    }
}
