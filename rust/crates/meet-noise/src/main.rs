use proton_meet_noise::Rnnoise;

fn main() {
    let rn = Rnnoise::new().unwrap();

    // Simulate a 10ms frame of silence or noise
    let noisy_frame = vec![0.1; 480];
    let mut clean = vec![0.0; 480];
    let check = rn.process_frame(&noisy_frame, &mut clean).unwrap();
    println!("Check: {}", check);
    println!("Denoised frame (first 5 samples): {:?}", &clean[..5]);
}
