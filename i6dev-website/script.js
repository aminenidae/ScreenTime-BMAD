// Mobile Navigation Toggle
const burger = document.querySelector('.burger');
const nav = document.querySelector('.nav-links');
const navLinks = document.querySelectorAll('.nav-links li');

burger.addEventListener('click', () => {
    // Toggle Nav
    nav.classList.toggle('active');
    
    // Burger Animation
    burger.classList.toggle('active');
    
    // Animate Links
    navLinks.forEach((link, index) => {
        if (link.style.animation) {
            link.style.animation = '';
        } else {
            link.style.animation = `navLinkFade 0.5s ease forwards ${index / 7 + 0.3}s`;
        }
    });
});

// Close mobile menu when clicking on a link
navLinks.forEach(link => {
    link.addEventListener('click', () => {
        nav.classList.remove('active');
        burger.classList.remove('active');
        
        navLinks.forEach(link => {
            link.style.animation = '';
        });
    });
});

// Smooth scrolling for navigation links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
        // Don't prevent default for external links or empty hrefs
        if (this.getAttribute('href') === '#' || this.getAttribute('href') === 'javascript:void(0)') return;
        
        e.preventDefault();
        
        const targetId = this.getAttribute('href');
        const targetSection = document.querySelector(targetId);
        
        if (targetSection) {
            // Close mobile menu if open
            nav.classList.remove('active');
            burger.classList.remove('active');
            
            navLinks.forEach(link => {
                link.style.animation = '';
            });
            
            // Scroll to section
            targetSection.scrollIntoView({
                behavior: 'smooth'
            });
        }
    });
});

// Simple animation for sections when they come into view
const sections = document.querySelectorAll('section');

const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.style.opacity = 1;
            entry.target.style.transform = 'translateY(0)';
        }
    });
}, { threshold: 0.1 });

sections.forEach(section => {
    section.style.opacity = 0;
    section.style.transform = 'translateY(20px)';
    section.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
    observer.observe(section);
});

// Form submission handling
const contactForm = document.getElementById('contactForm');

if (contactForm) {
    contactForm.addEventListener('submit', function(e) {
        e.preventDefault();
        
        // Get form values
        const name = document.getElementById('name').value;
        const email = document.getElementById('email').value;
        const subject = document.getElementById('subject').value;
        const message = document.getElementById('message').value;
        
        // In a real implementation, you would send this data to a server
        // For now, we'll just show a success message
        
        // Show success message
        alert(`Thank you ${name}! Your message has been sent. We'll get back to you soon.`);
        
        // Reset form
        contactForm.reset();
    });
}

// Header scroll effect
window.addEventListener('scroll', () => {
    const header = document.querySelector('header');
    if (window.scrollY > 100) {
        header.style.padding = '0.5rem 0';
        header.style.boxShadow = '0 2px 10px rgba(0, 0, 0, 0.3)';
    } else {
        header.style.padding = '1rem 0';
        header.style.boxShadow = '0 4px 6px rgba(0, 0, 0, 0.3)';
    }
});