;; Channel Configuration for Guix-Shimboot
;;
;; Purpose: Define channels including nonguix for firmware
;;
;; Usage: guix pull -C channels.scm

(use-modules (guix channels))

(cons* (channel
        (name 'nonguix)
        (url "https://gitlab.com/nonguix/nonguix")
        (introduction
         (make-channel-introduction
          "897c1a470da759236cc11798f4e0a5f7d4e597bc"
          (openpgp-fingerprint
           "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20EA D631 7A4A"))))
       %default-channels)