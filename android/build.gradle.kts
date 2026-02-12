plugins {
    id("com.google.gms.google-services") version "4.4.0" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Force consistent AndroidX versions to fix lStar attribute error
subprojects {
    configurations.configureEach {
        resolutionStrategy.force(
            "androidx.core:core:1.16.0",
            "androidx.core:core-ktx:1.16.0",
            "androidx.appcompat:appcompat:1.7.0"
        )
    }
}

// Force compileSdk 36 for all library modules (including Flutter plugins like printing)
subprojects {
    plugins.withType<com.android.build.gradle.LibraryPlugin> {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            compileSdk = 36
        }
    }
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
