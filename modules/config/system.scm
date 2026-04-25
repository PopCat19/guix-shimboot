;; Guix System Configuration for Shimboot
;;
;; Purpose: Define operating-system for Chromebook hardware
;;
;; UNTESTED — Not verified with `guix system build`
;;
;; This module:
;; - Imports board-specific configuration
;; - Sets up Shepherd services for vendor partition
;; - Configures basic system services
;; - Uses extlinux as placeholder bootloader (shimboot handles real boot)

(define-module (config system)
  #:use-module (gnu)
  #:use-module (gnu services)
  #:use-module (gnu system)
  #:use-module (gnu bootloader)
  #:use-module (gnu bootloader extlinux)
  #:use-module (config shimboot-services)
  #:use-module (boards)
  #:export (%shimboot-system))

(use-service-modules desktop networking ssh)
(use-package-modules linux)

(define %shimboot-system
  (operating-system
   (host-name "guix-shimboot")
   (timezone "America/New_York")
   (locale "en_US.utf8")

   ;; Use linux-libre kernel (ChromeOS kernel loaded via vendor partition)
   (kernel linux-libre)

   ;; Bootloader: extlinux as placeholder
   ;; Shimboot handles actual boot via ChromeOS kernel partition
   (bootloader
    (bootloader-configuration
     (bootloader extlinux-bootloader)
     (targets '("/dev/sda"))))

   ;; Filesystems: root on labeled partition
   ;; Shimboot pivot_root to this partition at boot
   (file-systems
    (cons (file-system
            (device (file-system-label "guix"))
            (mount-point "/")
            (type "ext4"))
          %base-file-systems))

   (users (cons (user-account
                 (name "user")
                 (group "users")
                 (supplementary-groups '("wheel" "netdev" "audio" "video"))
                 (home-directory "/home/user"))
                %base-user-accounts))

   (packages
    (append
     (list (specification->package "nss-certs")
           (specification->package "vim")
           (specification->package "htop"))
     %base-packages))

   (services
    (append
     (list

      ;; Shimboot vendor partition and modules
      (service shimboot-service-type
               (shimboot-configuration
                (board 'dedede)
                (wifi-modules (board-wifi-modules 'dedede))))

      ;; Basic networking
      (service network-manager-service-type)
      (service wpa-supplicant-service-type)

      ;; SSH for headless access
      (service openssh-service-type
               (openssh-configuration
                (permit-root-login 'prohibit-password))))

     %base-services))))

;; Entry point for guix system reconfigure
%shimboot-system