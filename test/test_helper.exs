# Generated `--deliver` configs call `:public_key` (CA certs for HTTPS). Mix
# prunes OTP apps mob_new itself doesn't depend on from the code path, so load
# it for the tests that evaluate those configs.
Mix.ensure_application!(:public_key)
ExUnit.start()
