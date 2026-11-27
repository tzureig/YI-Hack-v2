LDFLAGS ?= -static
OBJECTS = fwverify.o tweetnacl.o
all: fwverify

fw_sign_pub.h: ../fw_sign.pub
	printf 'static const unsigned char fw_sign_pub[32] = {' > $@
	tr -d ' \n' < ../fw_sign.pub | sed 's/../0x&,/g; s/,$$//' >> $@
	printf '};\n' >> $@

fwverify.o: fwverify.c fw_sign_pub.h tweetnacl.h
	$(CC) -c $< -Os -Wall -o $@

tweetnacl.o: tweetnacl.c tweetnacl.h
	$(CC) -c $< -Os -o $@

fwverify: $(OBJECTS)
	$(CC) $(OBJECTS) -Os $(LDFLAGS) -o $@

.PHONY: clean

clean:
	rm -f fwverify fw_sign_pub.h $(OBJECTS)
