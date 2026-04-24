;; Guix System Configuration for Shimboot
;;
;; Purpose: Define operating-system for Chromebook hardware
;;
;; This module:
;; - Imports board-specific configuration
;; - Sets up Shepherd services for vendor partition
;; - Configures basic system services

(define-module (config system)
  #:use-module (gnu)
  #:use-module (gnu services)
  #:use-module (gnu system)
  #:use-module (config shimboot-services)
  #:use-module (boards)
  #:export (%shimboot-system))

(use-service-modules desktop networking ssh)

(define %shimboot-system
  (operating-system
   (host-name "guix-shimboot")
   (timezone "America/New_York")
   (locale "en_US.utf8")

   ;; Use standard kernel (ChromeOS kernel via vendor partition)
   (kernel linux-libre)

   ;; Firmware handled by vendor partition
   ;; If using nonguix: (firmware linux-firmware)

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