;; Shimboot Service Definitions
;;
;; Purpose: Define Guix services for shimboot integration
;;
;; UNTESTED — Not verified with `guix system build`
;;
;; This module:
;; - Provides vendor partition mount service
;; - Provides kernel module loading service
;; - Integrates with Shepherd init system

(define-module (config shimboot-services)
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (shimboot-configuration
            shimboot-configuration?
            shimboot-service-type

            shimboot-vendor-service-type
            shimboot-module-loader-service-type))

;;; Configuration record

(define-record-type* <shimboot-configuration>
  shimboot-configuration
  make-shimboot-configuration
  shimboot-configuration?
  (board              shimboot-configuration-board
                      (default 'dedede))
  (wifi-modules      shimboot-configuration-wifi-modules
                     (default '()))
  (vendor-partition  shimboot-configuration-vendor-partition
                     (default #f)))

;;; Vendor partition mount service
;;; Binds vendor partition contents to rootfs lib directories

(define (vendor-mount-shepherd-service config)
  "Return shepherd service to mount vendor partition."
  (let ((vendor-part (or (shimboot-configuration-vendor-partition config)
                         "/dev/disk/by-partlabel/shimboot_rootfs:vendor")))
    (list (shepherd-service
           (provision '(vendor-filesystems))
           (requirement '(file-systems))
           (one-shot? #t)
           (modules '((ice-9 textual-ports)))
           (start
            #~(lambda ()
                (let ((vendor-part #$vendor-part)
                      (newroot "/"))
                  ;; Mount vendor partition
                  (unless (file-exists? "/run/vendor")
                    (mkdir-p "/run/vendor"))
                  (system* "mount" "-o" "ro" vendor-part "/run/vendor")

                  ;; Bind mount modules
                  (unless (file-exists? "/lib/modules")
                    (mkdir-p "/lib/modules"))
                  (system* "mount" "--bind"
                           "/run/vendor/lib/modules"
                           "/lib/modules")

                  ;; Bind mount firmware
                  (unless (file-exists? "/lib/firmware")
                    (mkdir-p "/lib/firmware"))
                  (system* "mount" "--bind"
                           "/run/vendor/lib/firmware"
                           "/lib/firmware")
                  #t)))
           (stop #~(lambda _ #f))))))

(define shimboot-vendor-service-type
  (service-type
   (name 'shimboot-vendor)
   (extensions
    (list (service-extension shepherd-root-service-type
                             vendor-mount-shepherd-service)))
   (description "Mount vendor partition and bind-mount drivers to rootfs.")))

;;; Kernel module loader service
;;; Loads board-specific WiFi modules

(define (module-loader-shepherd-service config)
  "Return shepherd service to load kernel modules."
  (let ((modules (shimboot-configuration-wifi-modules config)))
    (if (null? modules)
        '()
        (list (shepherd-service
               (provision '(kernel-modules))
               (requirement '(vendor-filesystems))
               (one-shot? #t)
               (start
                #~(lambda ()
                    (for-each
                     (lambda (mod)
                       (system* "modprobe" mod))
                     '#$modules)
                    #t)))))))

(define shimboot-module-loader-service-type
  (service-type
   (name 'shimboot-modules)
   (extensions
    (list (service-extension shepherd-root-service-type
                             module-loader-shepherd-service)))
   (description "Load kernel modules from vendor partition.")))

;;; Main shimboot service (combines vendor + modules)

(define shimboot-service-type
  (service-type
   (name 'shimboot)
   (extensions
    (list (service-extension shepherd-root-service-type
                             vendor-mount-shepherd-service)
          (service-extension shepherd-root-service-type
                             module-loader-shepherd-service)))
   (description "Full shimboot integration: vendor mount and module loading.")))